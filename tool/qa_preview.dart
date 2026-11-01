import 'dart:io';

import 'package:bagoo_buyer_mobile/main.dart' as app;
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../test/support/fake_buyer_repository.dart';
import '../test/support/no_network.dart';
import 'preview/buyer_device_preview.dart';

/// Native interaction checks use the real widgets with synthetic buyer data.
/// Unexpected requests fail locally, including image and unimplemented routes.
void main() {
  if (!kDebugMode || !Platform.isLinux) {
    throw UnsupportedError('The isolated QA preview requires debug Linux.');
  }
  HttpOverrides.global = NoNetworkHttpOverrides();
  WidgetsFlutterBinding.ensureInitialized();
  final repository = FakeBuyerRepository();
  (repository.session as FakeSession).profileResponse = const WebPage(
    'Buyer/Profile',
    {
      'auth': {'user': buyer},
      'user': {
        ...buyer,
        'email_verified_at': '2026-01-01',
        'phone': '09171234567',
      },
      'canUsePortal': true,
      'addresses': [],
      'orders': {'data': [], 'current_page': 1, 'last_page': 1},
      'orderCounts': {},
      'ordersCount': 0,
      'wallet': {
        'available': true,
        'can_request': true,
        'balance_cents': 0,
        'credit_requests': [],
      },
    },
  );
  final appKey = GlobalKey();
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Banner(
        message: 'ISOLATED QA',
        location: BannerLocation.topEnd,
        child: BuyerDevicePreview(
          builder: (context) => app.MainApp(
            key: appKey,
            repository: repository,
            theme: Theme.of(context),
            scrollBehavior: ScrollConfiguration.of(context),
          ),
        ),
      ),
    ),
  );
}
