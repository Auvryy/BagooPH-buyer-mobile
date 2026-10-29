import 'dart:convert';
import 'dart:io';

import 'package:bagoo_buyer_mobile/core/buyer_capabilities.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> contract({Object? google = false, Object? push = false}) =>
    {
      'contract_version': 1,
      'features': {'native_google_sign_in': google, 'device_push': push},
    };

void expectUnavailable(Object? payload) {
  final result = BuyerCapabilities.parse(payload);
  expect(result.isSupported, isFalse);
  expect(result.contractVersion, isNull);
  expect(result.nativeGoogleSignIn, isFalse);
  expect(result.devicePush, isFalse);
}

void main() {
  test('accepts the shared web fixture for the initial disabled contract', () {
    final fixture = jsonDecode(
      File('test/fixtures/buyer-mobile-capabilities-disabled.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    final payload = (fixture['response'] as Map)['body'];
    final result = BuyerCapabilities.parse(payload);
    expect(result.isSupported, isTrue);
    expect(result.contractVersion, 1);
    expect(result.nativeGoogleSignIn, isFalse);
    expect(result.devicePush, isFalse);
  });

  test('retains independent explicit capability flags', () {
    final google = BuyerCapabilities.parse(contract(google: true));
    expect(google.nativeGoogleSignIn, isTrue);
    expect(google.devicePush, isFalse);
    final push = BuyerCapabilities.parse(contract(push: true));
    expect(push.nativeGoogleSignIn, isFalse);
    expect(push.devicePush, isTrue);
  });

  test('refuses missing, coerced and unsupported contract versions', () {
    for (final version in [null, '1', 1.0, true, 0, 2, -1]) {
      expectUnavailable({
        ...contract(google: true),
        'contract_version': version,
      });
    }
    final missing = contract(google: true)..remove('contract_version');
    expectUnavailable(missing);
  });

  test('refuses non-object, absent and malformed feature containers', () {
    for (final payload in [null, true, 'enabled', [], 1]) {
      expectUnavailable(payload);
    }
    expectUnavailable({'contract_version': 1});
    for (final features in [null, true, 'enabled', [], 1]) {
      expectUnavailable({'contract_version': 1, 'features': features});
    }
  });

  test('a partial feature reply cannot enable the remaining capability', () {
    for (final features in [
      {'native_google_sign_in': true},
      {'device_push': true},
      <String, Object?>{},
    ]) {
      expectUnavailable({'contract_version': 1, 'features': features});
    }
  });

  test('truthy or malformed flags disable the entire optional contract', () {
    for (final value in [null, 'true', 'false', 1, 0, [], {}]) {
      expectUnavailable(contract(google: value, push: true));
      expectUnavailable(contract(google: true, push: value));
    }
  });

  test('compatible extra fields never become additional capability grants', () {
    final payload = contract();
    payload['future_feature'] = true;
    (payload['features'] as Map)['future_feature'] = true;
    final result = BuyerCapabilities.parse(payload);
    expect(result.isSupported, isTrue);
    expect(result.nativeGoogleSignIn, isFalse);
    expect(result.devicePush, isFalse);
  });
}
