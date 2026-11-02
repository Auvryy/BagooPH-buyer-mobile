import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/home/about_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_web_session.dart';

void main() {
  testWidgets('About hides policy links when a link targets another page', (
    tester,
  ) async {
    final session = ControlledWebSession()
      ..onPage = (_) async => const WebPage('Auth/Register', {
        'policies': {
          'required': true,
          'terms_version': '2026-10-12',
          'privacy_version': '2026-10-12',
          'terms_url': '/login',
          'privacy_url': '/privacy/2026-10-12',
        },
      });
    addTearDown(session.close);

    await tester.pumpWidget(
      MaterialApp(home: AboutBagooPage(repository: BuyerRepository(session))),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Account policy links could not be confirmed.'),
      findsOneWidget,
    );
    expect(find.text('Terms of Service'), findsNothing);
    expect(find.text('Privacy Policy'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
