import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/src/buyer_build_configuration.dart';

void main() {
  BuyerBuildConfiguration parse(
    Map<String, dynamic> config, {
    String platform = 'android',
    bool release = false,
  }) => BuyerBuildConfiguration.parse(
    config,
    platform: platform,
    release: release,
  );

  test(
    'one public origin derives the same native link host and iOS callback',
    () {
      final result = parse(
        {
          'BAGOO_BASE_URL': 'https://buyers.shop.ph',
          'BAGOO_GOOGLE_ENABLED': true,
          'BAGOO_GOOGLE_SERVER_CLIENT_ID': 'server.apps.googleusercontent.com',
          'BAGOO_GOOGLE_IOS_CLIENT_ID': 'ios.apps.googleusercontent.com',
        },
        platform: 'ios',
        release: true,
      );
      expect(result.linkHost, result.origin.host);
      expect(result.iosSettings, contains('BAGOO_LINK_HOST = buyers.shop.ph'));
      expect(result.iosSettings, contains('com.googleusercontent.apps.ios'));
    },
  );

  test('debug supports local origins without activating Google', () {
    final result = parse({
      'BAGOO_BASE_URL': 'http://localhost:8000',
    }, platform: 'linux');
    expect(result.google.enabled, isFalse);
    expect(result.iosSettings, contains('invalid.bagoo.google-disabled'));
  });

  test(
    'release rejects development origins and placeholder association hosts',
    () {
      for (final base in [
        'http://buyers.shop.ph',
        'https://buyers.shop.ph:8443',
        'https://localhost',
        'https://buyer.example.invalid',
        'https://buyer.example.test',
        'https://example.com',
        'https://buyer.example.org',
        'https://127.0.0.1',
        'https://[::1]',
      ]) {
        expect(
          () => parse({'BAGOO_BASE_URL': base}, release: true),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'configuration rejects secrets, ambiguous origins and wrong Google types',
    () {
      for (final values in <Map<String, dynamic>>[
        {},
        {'BAGOO_BASE_URL': 'https://user:password@buyers.shop.ph'},
        {'BAGOO_BASE_URL': 'https://buyers.shop.ph/api'},
        {'BAGOO_BASE_URL': 'https://buyers.shop.ph?key=value'},
        {'BAGOO_BASE_URL': 'https://buyers.shop.ph#fragment'},
        {'BAGOO_BASE_URL': 'https://foo%0abar.ph'},
        {
          'BAGOO_BASE_URL': 'https://buyers.shop.ph',
          'CLIENT_SECRET': 'do-not-bundle',
        },
        {
          'BAGOO_BASE_URL': 'https://buyers.shop.ph',
          'BAGOO_GOOGLE_ENABLED': 'true',
        },
        {
          'BAGOO_BASE_URL': 'https://buyers.shop.ph',
          'BAGOO_GOOGLE_ENABLED': true,
        },
        {
          'BAGOO_BASE_URL': 'https://buyers.shop.ph',
          'BAGOO_GOOGLE_SERVER_CLIENT_ID': 'bad-client',
        },
      ]) {
        expect(() => parse(values), throwsFormatException);
      }
      expect(
        () => parse({
          'BAGOO_BASE_URL': 'https://buyers.shop.ph',
          'BAGOO_GOOGLE_ENABLED': true,
          'BAGOO_GOOGLE_SERVER_CLIENT_ID': 'server.apps.googleusercontent.com',
        }, platform: 'ios'),
        throwsFormatException,
      );
    },
  );

  test(
    'check validates without writing native files and redacts rejected values',
    () async {
      final root = await Directory.systemTemp.createTemp('buyer-config-check-');
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/pubspec.yaml').writeAsString('name: fixture');
      await Directory('${root.path}/ios/Runner').create(recursive: true);
      await File('${root.path}/ios/Runner/Info.plist')
          .writeAsString('<plist/>');
      final config = File('${root.path}/owner.json');
      final tool = File('tool/buyer.dart').absolute.path;
      await config.writeAsString(
        jsonEncode({'BAGOO_BASE_URL': 'http://localhost:8000'}),
      );
      Future<ProcessResult> check() => Process.run('dart', [
        'run',
        tool,
        'check',
        '--config',
        config.path,
        '--platform',
        'linux',
      ], workingDirectory: root.path);
      final valid = await check();
      expect(valid.exitCode, 0, reason: '${valid.stderr}');
      expect(Directory('${root.path}/ios/Flutter').existsSync(), isFalse);
      await config.writeAsString(
        jsonEncode({
          'BAGOO_BASE_URL': 'http://localhost:8000',
          'CLIENT_SECRET': 'sensitive-marker',
        }),
      );
      final invalid = await check();
      expect(invalid.exitCode, 64);
      expect(
        '${invalid.stdout}${invalid.stderr}',
        isNot(contains('sensitive-marker')),
      );
      expect(Directory('${root.path}/ios/Flutter').existsSync(), isFalse);
    },
  );
}
