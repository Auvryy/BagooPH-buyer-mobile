import 'package:bagoo_buyer_mobile/core/buyer_repository.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/auth/policy_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_web_session.dart';

void main() {
  testWidgets('malformed policy paragraphs are not shown as complete text', (
    tester,
  ) async {
    final session = ControlledWebSession()
      ..onPage = (_) async => const WebPage('Auth/Policy', {
        'document': {
          'title': 'Terms of service',
          'introduction': 'Introductory text',
          'sections': [
            {'title': 'Important terms', 'paragraphs': 'not-a-list'},
          ],
        },
      });
    addTearDown(session.close);

    await tester.pumpWidget(
      MaterialApp(
        home: PolicyPage(
          repository: BuyerRepository(session),
          path: '/terms/current',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Policy text could not be fully confirmed. Try loading it again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Introductory text'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final (name, sections) in [
    ('a missing section list', null),
    (
      'a missing paragraph list',
      [
        {'title': 'Important terms'},
      ],
    ),
  ]) {
    testWidgets('policy rejects $name', (tester) async {
      final session = ControlledWebSession()
        ..onPage = (_) async => WebPage('Auth/Policy', {
          'document': {
            'title': 'Terms of Use',
            'version': '2026-10-12',
            'introduction': 'Do not display this partial policy.',
            'sections': sections,
          },
        });
      addTearDown(session.close);

      await tester.pumpWidget(
        MaterialApp(
          home: PolicyPage(
            repository: BuyerRepository(session),
            path: '/terms/current',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Policy text could not be fully confirmed. Try loading it again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Do not display this partial policy.'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
