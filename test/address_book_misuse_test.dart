import 'dart:async';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/profile/addresses_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'returns_misuse_test.dart' show returnPress;
import 'support/account_fixtures.dart';
import 'support/address_fixtures.dart';
import 'support/return_fixtures.dart';

void main() {
  late AccountFixtureRepository repository;
  late ValueNotifier<WebPage> page;
  int changes = 0;
  ReturnSession session() => repository.session as ReturnSession;
  setUp(() {
    repository = AccountFixtureRepository();
    page = ValueNotifier(addressPage());
    changes = 0;
    session().onGet = (_) async => addressLocationOptions();
    repository.onMutation = (_) async {
      final result = addressPage();
      result.props['flash'] = {'success': 'Delivery address saved.'};
      return result;
    };
  });
  tearDown(() {
    repository.session.close();
    page.dispose();
  });

  void check(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  }

  Future<void> open(WidgetTester tester, {bool edit = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ValueListenableBuilder<WebPage>(
          valueListenable: page,
          builder: (_, value, _) => Scaffold(
            body: AddressesSection(
              repository: repository,
              page: value,
              onChanged: (value) {
                changes++;
                page.value = value;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (edit) {
      await returnPress(tester, find.text('Edit').last);
      expect(
        find.widgetWithText(TextFormField, 'Recipient name'),
        findsOneWidget,
      );
      expect(session().getRequests, hasLength(1));
      expect(tester.takeException(), isNull);
    }
  }

  Finder save() => find.text('Save delivery address');
  Future<void> startSave(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(save()), alignment: .5);
    await tester.pumpAndSettle();
    expect(save().hitTestable(), findsOneWidget);
    await tester.tap(save());
    await tester.pump();
    expect(repository.calls, hasLength(1));
  }

  Future<void> newAddress(WidgetTester tester) async {
    page.value.props['addresses'] = <Map<String, dynamic>>[];
    await open(tester);
    await returnPress(tester, find.text('Add delivery address'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Recipient name'),
      'New recipient',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Mobile number'),
      '09171234567',
    );
    await returnPress(
      tester,
      find.widgetWithText(DropdownButtonFormField<String>, 'Barangay'),
    );
    await returnPress(tester, find.text('San Rafael').last);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Street / house / unit number'),
      '456 New Test Street',
    );
  }

  check(
    'valid saved address preserves coordinates and uses its own update path',
    (tester) async {
      await open(tester, edit: true);
      await returnPress(tester, save());
      final call = repository.calls.single;
      expect(call.path, '/buyer/addresses/2');
      expect(call.method, 'PATCH');
      expect(call.values['recipient_name'], 'Private recipient');
      expect(call.values['phone'], '09171234567');
      expect(call.values['latitude'], '14.0689');
      expect(call.values['longitude'], '121.3250');
      expect(call.values['postal_code'], '4000');
      expect(call.values['is_default'], false);
      expect(changes, 1);
    },
  );

  for (final beforeNavigation in [true, false]) {
    check(
      'address navigation cannot renew an expired buyer: $beforeNavigation',
      (tester) async {
        await open(tester);
        final edit = find.text('Edit').last;
        await tester.ensureVisible(edit);
        await tester.pumpAndSettle();
        if (beforeNavigation) session().clear();
        await tester.tap(edit);
        if (!beforeNavigation) session().clear();
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(TextFormField, 'Recipient name'),
          findsNothing,
        );
        expect(session().getRequests, isEmpty);
        expect(repository.calls, isEmpty);
      },
    );
  }

  check('expired address editor clears its draft before saving', (
    tester,
  ) async {
    await open(tester, edit: true);
    session().clear();
    await returnPress(tester, save());
    expect(repository.calls, isEmpty);
    expect(find.widgetWithText(TextFormField, 'Recipient name'), findsNothing);
  });

  check('address editor clears private drafts on resume after account expiry', (
    tester,
  ) async {
    await open(tester, edit: true);
    session().clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Recipient name'), findsNothing);
    expect(repository.calls, isEmpty);
  });

  check('an open delete confirmation cannot write under another buyer', (
    tester,
  ) async {
    await open(tester);
    await returnPress(tester, find.text('Delete'));
    session().clear();
    await returnPress(tester, find.text('Delete address'));
    expect(repository.calls, isEmpty);
    expect(find.text('Private recipient'), findsNothing);
  });

  check('a late address save cannot replace the changed account profile', (
    tester,
  ) async {
    final pending = Completer<WebPage>();
    repository.onMutation = (_) => pending.future;
    await open(tester, edit: true);
    await startSave(tester);
    session().clear();
    pending.complete(addressPage());
    await tester.pumpAndSettle();
    expect(changes, 0);
    expect(find.widgetWithText(TextFormField, 'Recipient name'), findsNothing);
  });

  check('a foreign address acknowledgement is not accepted', (tester) async {
    repository.onMutation = (_) async => addressPage(owner: 8);
    await open(tester, edit: true);
    await returnPress(tester, save());
    expect(changes, 0);
    expect(find.widgetWithText(TextFormField, 'Recipient name'), findsNothing);
  });

  for (final status in [401, 403, 419]) {
    check('address access failure $status clears the private draft', (
      tester,
    ) async {
      repository.onMutation = (_) async =>
          throw BackendException('Address access ended.', status: status);
      await open(tester, edit: true);
      await returnPress(tester, save());
      expect(changes, 0);
      expect(
        find.widgetWithText(TextFormField, 'Recipient name'),
        findsNothing,
      );
    });
  }

  check('a temporary address failure keeps the draft for a deliberate retry', (
    tester,
  ) async {
    repository.onMutation = (_) async =>
        throw const BackendException('Offline.', status: 503);
    await open(tester, edit: true);
    await returnPress(tester, save());
    final recipient = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Recipient name'),
    );
    expect(recipient.controller?.text, 'Private recipient');
    expect(changes, 0);
    repository.onMutation = (_) async => addressPage();
    await returnPress(tester, save());
    expect(repository.calls, hasLength(2));
    expect(changes, 1);
  });

  check('duplicate address save presses send one request', (tester) async {
    final pending = Completer<WebPage>();
    repository.onMutation = (_) => pending.future;
    await open(tester, edit: true);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(save()), alignment: .5);
    await tester.pumpAndSettle();
    for (var index = 0; index < 8; index++) {
      await tester.tap(save());
    }
    await tester.pump();
    expect(repository.calls, hasLength(1));
    pending.complete(addressPage());
    await tester.pumpAndSettle();
    expect(changes, 1);
  });

  check('an address change removes coordinates from the prior street', (
    tester,
  ) async {
    await open(tester, edit: true);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Street / house / unit number'),
      '456 Revised Street',
    );
    await returnPress(tester, save());
    expect(repository.calls.single.values['latitude'], isNull);
    expect(repository.calls.single.values['longitude'], isNull);
  });

  check(
    'canonical location correction removes obsolete coordinates and postal code',
    (tester) async {
      final address = (page.value.props['addresses'] as List).last as Map;
      address['province'] = 'Old Laguna';
      address['city'] = 'Old City';
      await open(tester, edit: true);
      await returnPress(tester, save());
      final values = repository.calls.single.values;
      expect(values['province'], 'Laguna');
      expect(values['city'], 'San Pablo City');
      expect(values['latitude'], isNull);
      expect(values['longitude'], isNull);
      expect(values['postal_code'], '');
    },
  );

  check('unavailable location choices block saving an address', (tester) async {
    session().onGet = (_) async => throw const BackendException(
      'Location service unavailable.',
      status: 503,
    );
    await open(tester, edit: true);
    final button = tester.widget<FilledButton>(
      find.ancestor(of: save(), matching: find.byType(FilledButton)).first,
    );
    expect(button.onPressed, isNull);
    expect(repository.calls, isEmpty);
    expect(find.text('Retry location choices'), findsOneWidget);
  });

  check('unapproved buyers cannot change delivery addresses', (tester) async {
    page.value = addressPage(eligible: false);
    await open(tester);
    for (final label in ['Edit', 'Delete', 'Set as default']) {
      for (final button in tester.widgetList<TextButton>(
        find.widgetWithText(TextButton, label),
      )) {
        expect(button.onPressed, isNull);
      }
    }
    expect(repository.calls, isEmpty);
  });

  check('approval changes while an editor is open block its old save', (
    tester,
  ) async {
    await open(tester, edit: true);
    page.value = addressPage(eligible: false);
    await tester.pumpAndSettle();
    await returnPress(tester, save());
    expect(repository.calls, isEmpty);
    expect(changes, 0);
  });

  check('repeated delete activations open one confirmation', (tester) async {
    await open(tester);
    final remove = find.text('Delete');
    await tester.ensureVisible(remove);
    await tester.pumpAndSettle();
    final activate = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Delete'))
        .onPressed!;
    for (var index = 0; index < 8; index++) {
      activate();
    }
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
    expect(repository.calls, isEmpty);
  });

  check(
    'account expiry hides private details inside an open address confirmation',
    (tester) async {
      await open(tester);
      await returnPress(tester, find.text('Delete'));
      session().clear();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.textContaining('Private recipient'), findsNothing);
      expect(find.text('Delete address'), findsNothing);
      expect(repository.calls, isEmpty);
    },
  );

  check(
    'first address creation uses native values and the server default rule',
    (tester) async {
      await newAddress(tester);
      await returnPress(tester, find.text('Add address'));
      final call = repository.calls.single;
      expect(call.path, '/buyer/addresses');
      expect(call.method, 'POST');
      expect(call.values['is_default'], true);
      expect(call.values['recipient_name'], 'New recipient');
      expect(call.values['barangay'], 'San Rafael');
      expect(call.values['latitude'], isNull);
      expect(call.values['longitude'], isNull);
      expect(changes, 1);
    },
  );

  check(
    'an uncertain address creation requires reviewing saved addresses before another post',
    (tester) async {
      repository.onMutation = (_) async => throw const BackendException(
        'The save result is unknown.',
        status: 503,
      );
      session().onPage = (_) async => addressPage();
      await newAddress(tester);
      await returnPress(tester, find.text('Add address'));
      await returnPress(tester, find.text('Add address'));
      expect(repository.calls, hasLength(1));
      await returnPress(tester, find.text('Review saved addresses'));
      expect(session().pageRequests, hasLength(1));
      expect(changes, 1);
      expect(
        find.widgetWithText(TextFormField, 'Recipient name'),
        findsNothing,
      );
    },
  );

  check(
    'an explicit rejected creation remains editable for a corrected attempt',
    (tester) async {
      repository.onMutation = (_) async => throw const BackendException(
        'Correct the rejected address.',
        status: 422,
      );
      await newAddress(tester);
      await returnPress(tester, find.text('Add address'));
      expect(repository.calls, hasLength(1));
      repository.onMutation = (_) async => addressPage();
      await returnPress(tester, find.text('Add address'));
      expect(repository.calls, hasLength(2));
      expect(changes, 1);
    },
  );

  check('late location choices cannot restore an expired address draft', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    session().onGet = (_) => pending.future;
    await open(tester);
    final edit = find.text('Edit').last;
    await tester.ensureVisible(edit);
    await tester.pumpAndSettle();
    await tester.tap(edit);
    await tester.pump(const Duration(milliseconds: 400));
    expect(session().getRequests, hasLength(1));
    session().clear();
    pending.complete(addressLocationOptions());
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Recipient name'), findsNothing);
    expect(repository.calls, isEmpty);
  });

  for (final entry in {
    'Mobile number': 'phone123',
    'Postal code (optional)': '12x4',
  }.entries) {
    check('address submission rejects raw invalid ${entry.key}', (
      tester,
    ) async {
      await open(tester, edit: true);
      final input = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, entry.key),
      );
      input.controller!.text = entry.value;
      await returnPress(tester, save());
      expect(repository.calls, isEmpty);
      if (entry.key == 'Mobile number') {
        expect(
          find.widgetWithText(TextFormField, entry.key).hitTestable(),
          findsOneWidget,
        );
      }
    });
  }
}
