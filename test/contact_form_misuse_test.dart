import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/uploads.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/auth/auth_shell.dart';
import 'package:bagoo_buyer_mobile/features/profile/personal_section.dart';
import 'package:bagoo_buyer_mobile/features/profile/profile_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_buyer_repository.dart';

class ContactRepository extends ProfileRepository {
  ContactRepository() : super(FakeBuyerRepository());
  int saves = 0;
  final page = WebPage('Buyer/Profile', {
    'auth': {'user': buyer},
    'user': {...buyer, 'phone': '09171234567'},
  });

  @override
  Future<WebPage> mutate(
    String endpoint,
    Map<String, dynamic> values, {
    String method = 'POST',
    String tab = 'account',
    List<UploadPart>? files,
    bool requireMessage = true,
  }) async {
    saves++;
    return page;
  }
}

void main() {
  testWidgets('phone keyboard rejects letters and mixed pasted numbers', (
    tester,
  ) async {
    final controller = TextEditingController(text: '0917');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuthField(
            label: 'Mobile number',
            controller: controller,
            keyboardType: TextInputType.phone,
          ),
        ),
      ),
    );
    final input = find.byType(TextFormField);
    await tester.enterText(input, '0917abc');
    expect(controller.text, '0917');
    for (final value in [
      'call 09171234567',
      '０９１７１２３４５６７',
      '09171234567 ext 1',
      '++639171234567',
      '0917+1234567',
    ]) {
      await tester.enterText(input, value);
      expect(controller.text, '0917', reason: 'Reject the whole edit: $value');
    }
    await tester.enterText(input, '+63 (917) 123-4567');
    expect(controller.text, '+63 (917) 123-4567');
  });

  for (final invalid in [
    'letters',
    '0917',
    '0212345678',
    '+14155552671',
    '09171234567\n',
  ]) {
    testWidgets('profile rejects invalid contact before saving: $invalid', (
      tester,
    ) async {
      final repository = ContactRepository();
      addTearDown(repository.session.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: Scaffold(
            body: PersonalSection(
              repository: repository,
              page: repository.page,
              onChanged: (_) {},
              onIdentity: () {},
            ),
          ),
        ),
      );
      final phone = find.widgetWithText(TextFormField, 'Mobile contact');
      await tester.ensureVisible(phone);
      await tester.pumpAndSettle();
      // Controller assignment bypasses keyboard filtering, as autofill or a
      // future caller can. Submission must still validate the full number.
      tester.widget<TextFormField>(phone).controller!.text = invalid;
      final save = find.widgetWithText(FilledButton, 'Save Profile Changes');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      expect(save.hitTestable(), findsOneWidget);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repository.saves, 0);
    });
  }
}
