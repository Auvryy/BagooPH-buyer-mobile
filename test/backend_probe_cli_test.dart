import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'the backend probe runs in standalone Dart before validating arguments',
    () async {
      final result = await Process.run('dart', [
        'run',
        'tool/check_backend.dart',
      ]);
      expect(result.exitCode, 64, reason: result.stderr.toString());
      expect(
        result.stderr,
        contains('Usage: dart run tool/check_backend.dart <BACKEND_ORIGIN>'),
      );
    },
  );
}
