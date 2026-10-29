import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/features/auth/auth_shell.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_repository.dart';
import 'package:bagoo_buyer_mobile/features/profile/returns_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'returns_misuse_test.dart' show returnPress;
import 'support/return_fixtures.dart';

void main() {
  testWidgets('numeric account input rejects mixed edits and preserves zeros', (
    tester,
  ) async {
    final controller = TextEditingController(text: '0123');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuthField(
            label: 'Postal code',
            controller: controller,
            keyboardType: TextInputType.number,
          ),
        ),
      ),
    );
    final input = find.byType(TextFormField);
    for (final value in ['abc', '123x', '-1', '1.5', '１２']) {
      await tester.enterText(input, value);
      expect(controller.text, '0123', reason: 'Reject the whole edit: $value');
    }
    await tester.enterText(input, '001234');
    expect(controller.text, '001234');
    await tester.enterText(input, '');
    expect(controller.text, isEmpty);
  });

  testWidgets('return quantity rejects letters and mixed pastes before save', (
    tester,
  ) async {
    final session = ReturnSession();
    addTearDown(session.close);
    session.onPage = (_) async => returnForm();
    await tester.pumpWidget(
      MaterialApp(
        theme: BagooTheme.light,
        home: ReturnsPage(
          repository: ProfileRepository(BuyerRepository(session)),
          orderId: 11,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await returnPress(
      tester,
      find.widgetWithText(CheckboxListTile, 'Test purchase'),
    );
    final input = find.widgetWithText(TextFormField, 'Quantity to return');
    final controller = tester.widget<TextFormField>(input).controller!;
    for (final value in ['ab', '2x', '-1', '.2', '２']) {
      await tester.enterText(input, value);
      expect(controller.text, '1', reason: value);
    }
    await tester.enterText(input, '2');
    expect(controller.text, '2');
    expect(session.submissions, isEmpty);
  });
}
