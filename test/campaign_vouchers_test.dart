import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/promotions/campaign_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_buyer_repository.dart';

void main() {
  testWidgets(
    'the event shows its top three vouchers until the buyer asks for all',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 2400);
      addTearDown(tester.view.reset);
      final repo = FakeBuyerRepository();
      addTearDown(repo.session.close);
      final page = WebPage('Buyer/Campaign', {
        'auth': {
          'user': {'id': 1, 'name': 'Ana', 'role': 'buyer'},
        },
        'serverNow': '2026-12-01T00:00:00Z',
        'campaign': {
          'id': 3,
          'slug': 'payday',
          'title': 'Payday Mega Sale',
          'badge': 'PAYDAY DEAL',
          'banner_url': null,
          'starts_at': '2026-11-30T00:00:00Z',
          'ends_at': '2026-12-02T00:00:00Z',
          'status': 'live',
        },
        'vouchers': [
          for (var id = 1; id <= 5; id++)
            {
              'id': id,
              'code': 'CODE$id',
              'discount_type': 'fixed',
              'discount_value': 50,
              'min_spend': 300,
              'max_discount': 50,
              'issuer': 'platform',
              'claim_limit': null,
              'claimed_count': 0,
              'sold_out': false,
              'claimed': false,
            },
        ],
        'products': [],
        'categories': [],
        'allCampaigns': [],
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: BagooTheme.light,
          home: CampaignPage(repository: repo, initial: page),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      for (final code in ['CODE1', 'CODE2', 'CODE3']) {
        expect(find.text(code), findsOneWidget);
      }
      expect(find.text('CODE4'), findsNothing);
      await tester.tap(find.text('Show all 5 vouchers'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('CODE5'), findsOneWidget);
      expect(find.text('Show fewer vouchers'), findsOneWidget);
    },
  );
}
