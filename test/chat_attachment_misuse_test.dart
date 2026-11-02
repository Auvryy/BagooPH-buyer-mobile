import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/uploads.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/products/chat_page.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_web_session.dart';
import 'support/return_fixtures.dart';

Map<String, dynamic> _message(int id, {String text = '', bool mine = false}) =>
    {
      'id': id,
      'sender_id': mine ? 7 : 3,
      'receiver_id': mine ? 3 : 7,
      'message': text,
      'created_at': '2026-10-28T00:00:00Z',
    };

class _UploadSession extends ControlledWebSession {
  final uploads =
      <({String path, Map<String, dynamic> values, List<UploadPart> files})>[];
  bool failNext = true;

  @override
  Future<Map<String, dynamic>> uploadJson(
    String path,
    Map<String, dynamic> values,
    List<UploadPart> files, {
    String? referer,
  }) async {
    uploads.add((path: path, values: Map.of(values), files: List.of(files)));
    if (failNext) {
      failNext = false;
      throw const BackendException('Temporary upload issue.');
    }
    return {'success': true, 'message': _message(2, mine: true)};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FileSelectorPlatform originalPicker;
  late FixtureFileSelector picker;

  setUp(() {
    originalPicker = FileSelectorPlatform.instance;
    picker = FixtureFileSelector()..next = returnPhoto();
    FileSelectorPlatform.instance = picker;
  });

  tearDown(() => FileSelectorPlatform.instance = originalPicker);

  test('chat mutation rejects a fractional server message ID', () async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    session.onPost = (_) async => {
      'success': true,
      'message': {'id': 2.5},
    };

    await expectLater(
      BuyerRepository(session).sendMessage({
        'receiver_id': 3,
        'message': 'Hello',
        'request_key': 'synthetic-request-key',
      }),
      throwsA(isA<BackendException>()),
    );
    expect(session.posts, hasLength(1));
    expect(session.posts.single.path, '/chat/send');
  });

  test(
    'chat history rejects malformed text and impossible timestamps',
    () async {
      final session = ControlledWebSession();
      addTearDown(session.close);
      for (final malformed in [
        {
          ..._message(2),
          'message': <String, String>{'unexpected': 'text'},
        },
        {..._message(2), 'created_at': '2026-02-30T00:00:00Z'},
      ]) {
        session.onGet = (_) async => {
          'messages': [_message(1, text: 'Earlier'), malformed],
        };

        await expectLater(
          BuyerRepository(session).messages(3),
          throwsA(isA<BackendException>()),
        );
      }
      expect(session.getRequests, hasLength(2));
      expect(
        session.getRequests.every((path) => path == '/chat/messages/3'),
        isTrue,
      );
    },
  );

  testWidgets('a send confirmation for another conversation is not shown', (
    tester,
  ) async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    session.onGet = (_) async => {'messages': <Map<String, dynamic>>[]};
    session.onPost = (_) async => {
      'success': true,
      'message': {
        ..._message(9, text: 'Unexpected response', mine: true),
        'receiver_id': 88,
      },
    };

    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ChatPage(
          repository: BuyerRepository(session),
          userId: 7,
          receiverId: 3,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'My message');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();

    expect(find.text('Unexpected response'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'My message',
    );
    expect(find.text('Your message was not confirmed.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('malformed shop user ID never selects another chat recipient', (
    tester,
  ) async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    session.onGet = (_) async => {'messages': <Map<String, dynamic>>[]};
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ChatPage(
          repository: BuyerRepository(session),
          userId: 7,
          product: {
            'id': 1,
            'shop': {'id': 2, 'user_id': 12.5, 'name': 'Test shop'},
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(session.getRequests, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('non-positive explicit recipient never opens a chat', (
    tester,
  ) async {
    final session = ControlledWebSession();
    addTearDown(session.close);
    session.onGet = (_) async => {'messages': <Map<String, dynamic>>[]};
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ChatPage(
          repository: BuyerRepository(session),
          userId: 7,
          receiverId: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(session.getRequests, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed photo-only send keeps the same attachment intent', (
    tester,
  ) async {
    final session = _UploadSession();
    addTearDown(session.close);
    session.onGet = (_) async => {
      'messages': [_message(1, text: 'Earlier')],
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ChatPage(
          repository: BuyerRepository(session),
          userId: 7,
          receiverId: 3,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Attach a photo'));
    await tester.pumpAndSettle();
    expect(picker.calls, 1);
    expect(find.text('photo.png'), findsOneWidget);

    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(session.uploads, hasLength(1));
    expect(session.uploads.single.path, '/chat/send');
    expect(find.text('photo.png'), findsOneWidget);
    expect(find.text('Temporary upload issue.'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();

    expect(session.uploads, hasLength(2));
    expect(session.uploads[1].values['request_key'], isNotEmpty);
    expect(
      session.uploads[0].values['request_key'],
      session.uploads[1].values['request_key'],
    );
    for (final upload in session.uploads) {
      expect(upload.values['message'], '');
      expect(upload.files, hasLength(1));
      expect(upload.files.single.field, 'attachment');
      expect(upload.files.single.mime, 'image/png');
      expect(upload.files.single.bytes, returnPhotoBytes());
    }
    expect(find.text('photo.png'), findsNothing);
    expect(picker.calls, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
