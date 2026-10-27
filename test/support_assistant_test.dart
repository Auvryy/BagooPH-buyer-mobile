import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/products/chat_page.dart';
import 'package:bagoo_buyer_mobile/features/support/support_assistant_page.dart';
import 'package:bagoo_buyer_mobile/features/support/support_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_web_session.dart';
import 'support/fake_buyer_repository.dart' show buyer;

Finder _input(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      160,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _reveal(tester, finder);
  await tester.tap(finder.first);
  await tester.pump();
}

Widget _app(
  BuyerRepository repository, {
  int owner = 7,
  bool available = true,
  double scale = 1,
  double keyboard = 0,
}) => MaterialApp(
  theme: BagooTheme.light,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(scale),
      viewInsets: EdgeInsets.only(bottom: keyboard),
      disableAnimations: true,
    ),
    child: child!,
  ),
  home: SupportAssistantPage(
    key: const ValueKey('support'),
    repository: repository,
    user: {...buyer, 'id': owner},
    available: available,
  ),
);

void main() {
  late ControlledWebSession session;
  late BuyerRepository repository;

  setUp(() {
    session = ControlledWebSession();
    repository = BuyerRepository(session);
  });
  tearDown(() => session.close());

  test(
    'uses the existing support contract and sanitizes suggested questions',
    () async {
      session.onPost = (_) async => {
        'reply': '  Check your order timeline.  ',
        'suggested_questions': [
          '  Where is my order? ',
          null,
          '',
          'Where is my order?',
          List.filled(1001, 'x').join(),
          'Contact Customer Care',
          'Return details',
          'Extra suggestion',
        ],
      };
      final answer = await SupportAssistantRepository(repository)
          .ask('  Please check my order.  ', orderNumber: '  ORDER-1  ');
      expect(session.posts.single.path, '/buyer/support/assistant');
      expect(session.posts.single.method, 'POST');
      expect(session.posts.single.values, {
        'message': 'Please check my order.',
        'order_number': 'ORDER-1',
      });
      expect(answer.reply, 'Check your order timeline.');
      expect(answer.suggestions, [
        'Where is my order?',
        'Contact Customer Care',
        'Return details',
      ]);
    },
  );

  test('rejects invalid local fields and unconfirmed server replies', () async {
    final support = SupportAssistantRepository(repository);
    for (final question in ['', List.filled(1001, 'x').join()]) {
      await expectLater(
        support.ask(question),
        throwsA(isA<BackendException>()),
      );
    }
    await expectLater(
      support.ask('Help', orderNumber: List.filled(51, 'x').join()),
      throwsA(
        isA<BackendException>().having(
          (error) => error.fields.containsKey('order_number'),
          'order error',
          true,
        ),
      ),
    );
    expect(session.posts, isEmpty);
    for (final reply in [null, '', '   ', 5]) {
      session.onPost = (_) async => {'reply': reply};
      await expectLater(support.ask('Help'), throwsA(isA<BackendException>()));
    }
    expect(
      session.posts.every((post) => !post.values.containsKey('order_number')),
      isTrue,
    );
  });

  testWidgets(
    'a suggested question stays editable and survives a failed send',
    (tester) async {
      var calls = 0;
      session.onPost = (_) async {
        if (++calls == 1) {
          throw const BackendException(
            'Support is unavailable. Try again.',
            status: 503,
          );
        }
        return {
          'reply': 'Use your order timeline for the latest update.',
          'suggested_questions': <String>[],
        };
      };
      await tester.pumpWidget(_app(repository));
      await _tap(tester, find.text('Where is my latest order?'));
      expect(session.posts, isEmpty);
      expect(
        tester.widget<TextField>(_input('Message')).controller!.text,
        'Where is my latest order?',
      );
      await _tap(tester, find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(_input('Message')).controller!.text,
        'Where is my latest order?',
      );
      await _tap(tester, find.text('Try again'));
      await tester.pumpAndSettle();
      expect(session.posts, hasLength(2));
      expect(session.posts[0].values, session.posts[1].values);
      expect(
        tester.widget<TextField>(_input('Message')).controller!.text,
        isEmpty,
      );
      expect(
        find.text('Use your order timeline for the latest update.'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsNothing);
    },
  );

  testWidgets('prevents duplicate sends and ignores a reply after disposal', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    session.onPost = (_) => pending.future;
    await tester.pumpWidget(_app(repository));
    await tester.enterText(_input('Message'), 'Please check my order.');
    await _tap(tester, find.byTooltip('Send message'));
    await tester.tap(find.byTooltip('Send message'));
    await tester.pump();
    expect(session.posts, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete({'reply': 'Old reply'});
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'retains order and message fields with server validation feedback',
    (tester) async {
      session.onPost = (_) async => throw const BackendException(
        'Check your details.',
        status: 422,
        fields: {'order_number': 'Check the order number.'},
      );
      await tester.pumpWidget(_app(repository));
      await _tap(tester, find.text('Add an order number'));
      await tester.enterText(_input('Order number (optional)'), 'ORDER-1');
      await tester.enterText(_input('Message'), 'Please check delivery.');
      await _tap(tester, find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      final order = tester.widget<TextField>(_input('Order number (optional)'));
      expect(order.controller!.text, 'ORDER-1');
      expect(order.decoration!.errorText, 'Check the order number.');
      expect(
        tester.widget<TextField>(_input('Message')).controller!.text,
        'Please check delivery.',
      );
    },
  );

  testWidgets(
    'hides protected conversation state when access or session ends',
    (tester) async {
      await tester.pumpWidget(_app(repository, available: false));
      expect(_input('Message'), findsNothing);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton &&
                    widget.tooltip == 'Chat with Bagoo Customer Care',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(session.posts, isEmpty);
      session.onPost = (_) async =>
          throw const BackendException('Session expired.', status: 419);
      await tester.pumpWidget(_app(repository));
      await tester.enterText(_input('Message'), 'Private order question');
      await _tap(tester, find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to continue'), findsOneWidget);
      expect(find.text('Private order question'), findsNothing);
      expect(_input('Message'), findsNothing);
    },
  );

  testWidgets('does not render a late reply for a different buyer', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    session.onPost = (_) => pending.future;
    await tester.pumpWidget(_app(repository));
    await tester.enterText(_input('Message'), 'Old buyer question');
    await _tap(tester, find.byTooltip('Send message'));
    await tester.pumpWidget(_app(repository, owner: 8));
    pending.complete({'reply': 'Old buyer private reply'});
    await tester.pumpAndSettle();
    expect(find.text('Old buyer private reply'), findsNothing);
    expect(find.text('Old buyer question'), findsNothing);
    expect(
      tester.widget<TextField>(_input('Message')).controller!.text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Customer Care opens the existing native photo-capable chat', (
    tester,
  ) async {
    session.onGet = (_) async => {'messages': <dynamic>[]};
    await tester.pumpWidget(_app(repository));
    await _tap(tester, find.byTooltip('Chat with Bagoo Customer Care'));
    await tester.pumpAndSettle();
    final chat = tester.widget<ChatPage>(find.byType(ChatPage));
    expect(chat.receiverId, 2);
    expect(chat.userId, 7);
    expect(chat.canAttach, isTrue);
    expect(session.getRequests, ['/chat/messages/2']);
    expect(session.posts, isEmpty);
  });

  testWidgets('draft and order survive a move to a short keyboard layout', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 667);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(_app(repository));
    await _tap(tester, find.text('Add an order number'));
    await tester.enterText(_input('Order number (optional)'), 'ORDER-1');
    await tester.enterText(_input('Message'), 'Keep my delivery question.');
    tester.view.physicalSize = const Size(667, 375);
    await tester.pumpWidget(_app(repository, scale: 2, keyboard: 180));
    await _reveal(tester, _input('Order number (optional)'));
    expect(
      tester
          .widget<TextField>(_input('Order number (optional)'))
          .controller!
          .text,
      'ORDER-1',
    );
    await _reveal(tester, _input('Message'));
    expect(
      tester.widget<TextField>(_input('Message')).controller!.text,
      'Keep my delivery question.',
    );
    expect(tester.takeException(), isNull);
    expect(session.posts, isEmpty);
  });

  for (final layout in [
    (size: const Size(375, 667), scale: 1.0, keyboard: 0.0),
    (size: const Size(375, 667), scale: 2.0, keyboard: 220.0),
    (size: const Size(667, 375), scale: 1.0, keyboard: 180.0),
    (size: const Size(667, 375), scale: 2.0, keyboard: 180.0),
    (size: const Size(1024, 768), scale: 2.0, keyboard: 250.0),
    (size: const Size(320, 568), scale: 2.0, keyboard: 220.0),
  ]) {
    testWidgets('support remains usable for layout $layout', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = layout.size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        _app(repository, scale: layout.scale, keyboard: layout.keyboard),
      );
      await _tap(tester, find.text('Add an order number'));
      await _reveal(tester, _input('Order number (optional)'));
      await tester.enterText(_input('Order number (optional)'), 'ORDER-1');
      await _reveal(tester, _input('Message'));
      await tester.enterText(_input('Message'), 'Please check my delivery.');
      await _reveal(tester, find.byTooltip('Send message'));
      expect(find.byTooltip('Send message').hitTestable(), findsOneWidget);
      expect(
        tester.getBottomRight(find.byTooltip('Send message')).dy,
        lessThanOrEqualTo(layout.size.height - layout.keyboard),
      );
      expect(tester.takeException(), isNull);
      expect(session.posts, isEmpty);
    });
  }
}
