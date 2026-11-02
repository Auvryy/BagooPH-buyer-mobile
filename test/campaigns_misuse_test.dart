import 'dart:io';

import 'package:bagoo_buyer_mobile/app/theme.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:bagoo_buyer_mobile/features/home/campaigns.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/no_network.dart';

void main() {
  final originalOverrides = HttpOverrides.current;
  setUpAll(() => HttpOverrides.global = NoNetworkHttpOverrides());
  tearDownAll(() => HttpOverrides.global = originalOverrides);

  testWidgets('campaign indicator follows the list after banners refresh', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = WebSession(Uri.parse('http://backend.test'));
    addTearDown(session.close);
    final banners = List.generate(
      3,
      (index) => {
        'id': index + 1,
        'title': 'Campaign ${index + 1}',
        'image': 'public/campaign-${index + 1}.jpg',
      },
    );

    Widget page(List<Map<String, dynamic>> items) => MaterialApp(
      theme: BagooTheme.light,
      home: Scaffold(
        body: Campaigns(
          key: const ValueKey('campaigns'),
          banners: items,
          session: session,
          onOpen: (_) {},
        ),
      ),
    );

    await tester.pumpWidget(page(banners));
    await tester.pumpAndSettle();
    final pager = find.byType(PageView);
    await tester.drag(pager, const Offset(-400, 0));
    await tester.pumpAndSettle();
    await tester.drag(pager, const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.text('3 of 3'), findsOneWidget);

    await tester.pumpWidget(page(banners.take(2).toList()));
    await tester.pumpAndSettle();

    expect(find.text('2 of 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
