import 'dart:convert';
import 'dart:io';

import 'src/buyer_build_configuration.dart';

const usage =
    'Usage: dart run tool/buyer.dart <check|run|apk|appbundle|ios> '
    '--config <public-config.json> --platform <android|ios|linux> '
    '[--device <device-id>] [--release] [--no-codesign for ios]';

Future<void> main(List<String> args) async {
  try {
    if (args.isEmpty || args.contains('--help')) {
      stdout.writeln(usage);
      return;
    }
    final command = args.first;
    if (!['check', 'run', 'apk', 'appbundle', 'ios'].contains(command)) {
      throw const FormatException(usage);
    }
    final values = <String, String>{};
    var release = ['apk', 'appbundle', 'ios'].contains(command);
    var noCodesign = false;
    for (var index = 1; index < args.length; index++) {
      final key = args[index];
      if (key == '--release') {
        release = true;
        continue;
      }
      if (key == '--no-codesign' && command == 'ios') {
        noCodesign = true;
        continue;
      }
      if (!['--config', '--platform', '--device'].contains(key) ||
          values.containsKey(key) ||
          index + 1 >= args.length ||
          args[index + 1].startsWith('--')) {
        throw const FormatException(usage);
      }
      values[key] = args[++index];
    }
    final path = values['--config'];
    final platform = values['--platform'];
    if (path == null || platform == null) throw const FormatException(usage);
    if (['apk', 'appbundle'].contains(command) && platform != 'android' ||
        command == 'ios' && platform != 'ios') {
      throw const FormatException(
        'Choose the platform matching the build command.',
      );
    }
    if (!File('pubspec.yaml').existsSync() ||
        !File('ios/Runner/Info.plist').existsSync()) {
      throw const FormatException('Run from the buyer mobile repository root.');
    }
    final file = File(path);
    if (!file.existsSync()) {
      throw const FormatException(
        'Public configuration file is missing. Copy config/buyer.example.json to config/buyer.local.json.',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } on FormatException {
      throw const FormatException('Public configuration must be valid JSON.');
    }
    final config = BuyerBuildConfiguration.parse(
      decoded,
      platform: platform,
      release: release,
    );
    if (release &&
        platform == 'android' &&
        !File('android/key.properties').existsSync()) {
      throw const FormatException(
        'Android release requires owner signing in ignored android/key.properties. See docs/release-setup.md.',
      );
    }
    if (command == 'check') {
      stdout.writeln(
        'Public configuration is valid for $platform ${release ? 'release' : 'debug'}. Native settings derive the same buyer host.',
      );
      stdout.writeln(
        'This does not verify OAuth registration, signing credentials, associations or a deployed backend.',
      );
      return;
    }
    if (platform == 'ios') {
      await File('ios/Flutter/Bagoo.local.xcconfig')
          .writeAsString(config.iosSettings);
    }
    final flutterArgs = command == 'run'
        ? [
            'run',
            if (values['--device'] case final device?) ...['-d', device],
            release ? '--release' : '--debug',
          ]
        : ['build', command, '--release', if (noCodesign) '--no-codesign'];
    flutterArgs.add('--dart-define-from-file=${file.absolute.path}');
    final process = await Process.start(
      'flutter',
      flutterArgs,
      mode: ProcessStartMode.inheritStdio,
      environment: {'ORG_GRADLE_PROJECT_BAGOO_LINK_HOST': config.linkHost},
    );
    exitCode = await process.exitCode;
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
  } on FileSystemException {
    stderr.writeln(
      'Could not read or write buyer owner configuration. Check file permissions.',
    );
    exitCode = 74;
  } on ProcessException {
    stderr.writeln(
      'Could not start Flutter. Check that Flutter is installed and on PATH.',
    );
    exitCode = 69;
  }
}
