import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/testing/coverage_report.dart' as coverage;

void main() {
  late Directory root;
  late File lcov;
  late List<String> messages;

  setUp(() {
    root = Directory.systemTemp.createTempSync('buyer-coverage-');
    Directory.fromUri(root.uri.resolve('lib/')).createSync();
    File.fromUri(root.uri.resolve('lib/main.dart'))
        .writeAsStringSync('void main() {}');
    lcov = File.fromUri(root.uri.resolve('test.lcov'));
    messages = [];
  });
  tearDown(() => root.deleteSync(recursive: true));

  String record(String source, String counters) =>
      'SF:$source\n$counters\nend_of_record\n';
  const hit = 'DA:1,2\nBRDA:1,0,0,2';

  test(
    'complete means every inventoried source has all reported branches hit',
    () {
      final report = coverage.buildCoverageReport(
        record('lib/main.dart', hit),
        root,
      );
      expect(report['complete'], isTrue);
      expect(report['branchesHit'], 1);
      expect(report['branchPercent'], 100);
      expect(report['unmeasuredFiles'], isEmpty);
    },
  );

  test(
    'uninstrumented tool source prevents a false 100% completeness claim',
    () {
      Directory.fromUri(root.uri.resolve('tool/nested/'))
          .createSync(recursive: true);
      File.fromUri(root.uri.resolve('tool/nested/build.dart'))
          .writeAsStringSync('void main() {}');
      File.fromUri(root.uri.resolve('tool/notes.md'))
          .writeAsStringSync('Ignored non-Dart source.');
      final report = coverage.buildCoverageReport(
        record('lib/main.dart', hit),
        root,
      );
      expect(report['branchPercent'], 100);
      expect(report['complete'], isFalse);
      expect(report['sourceFiles'], 2);
      expect(report['unmeasuredFiles'], ['tool/nested/build.dart']);
      expect(
        coverage.coverageMarkdown(report),
        contains('| tool/nested/build.dart | false |'),
      );
    },
  );

  test(
    'unknown hits and distinct alternatives on a line stay in inventory',
    () {
      final report = coverage.buildCoverageReport(
        record('lib/main.dart', 'DA:1,0,checksum\nBRDA:1,0,0,-\nBRDA:1,0,1,4'),
        root,
      );
      expect(report['branchesFound'], 2);
      expect(report['branchesHit'], 1);
      expect(report['branchPercent'], 50);
      expect(report['complete'], isFalse);
      final file = (report['files'] as Map)['lib/main.dart'] as Map;
      expect(file['uncoveredBranches'], ['1:0:0']);
      expect(file['uncoveredLines'], [1]);
    },
  );

  test('repeated file records merge observations without double counting', () {
    final report = coverage.buildCoverageReport(
      record('lib/main.dart', 'DA:1,0\nBRDA:1,0,0,0') +
          record(File.fromUri(root.uri.resolve('lib/main.dart')).path, hit) +
          record(
            root.uri.resolve('lib/main.dart').toString(),
            'DA:1,0\nBRDA:1,0,0,0',
          ),
      root,
    );
    expect(report['branchesFound'], 1);
    expect(report['branchesHit'], 1);
    expect(report['complete'], isTrue);
    final file = (report['files'] as Map)['lib/main.dart'] as Map;
    expect(file['linesFound'], 1);
    expect(file['linesHit'], 1);
  });

  test('dependency and outside-workspace counters cannot inflate coverage', () {
    final report = coverage.buildCoverageReport(
      record('../outside.dart', hit) + record('test/fixture.dart', hit),
      root,
    );
    expect(report['branchesFound'], 0);
    expect(report['branchPercent'], isNull);
    expect(report['complete'], isFalse);
    expect(report['measuredFiles'], 0);
  });

  test('native browser fixture source remains in the workspace inventory', () {
    Directory.fromUri(root.uri.resolve('e2e/')).createSync();
    File.fromUri(root.uri.resolve('e2e/native_fixture.dart'))
        .writeAsStringSync('void main() {}');
    final report = coverage.buildCoverageReport(
      record('lib/main.dart', hit),
      root,
    );
    expect(report['sourceFiles'], 2);
    expect(report['unmeasuredFiles'], ['e2e/native_fixture.dart']);
    expect(report['complete'], isFalse);
  });

  test('an empty source record cannot make an unmeasured file pass', () {
    File.fromUri(root.uri.resolve('lib/other.dart'))
        .writeAsStringSync('void other() {}');
    final report = coverage.buildCoverageReport(
      record('lib/main.dart', hit) + record('lib/other.dart', ''),
      root,
    );
    expect(report['branchPercent'], 100);
    expect(report['measuredFiles'], 1);
    expect(report['unmeasuredFiles'], ['lib/other.dart']);
    expect(report['complete'], isFalse);
  });

  test('empty inventory or a branchless measurement never passes the gate', () {
    final report = coverage.buildCoverageReport(
      record('lib/main.dart', 'DA:1,1'),
      root,
    );
    expect(report['complete'], isFalse);
    File.fromUri(root.uri.resolve('lib/main.dart')).deleteSync();
    final empty = coverage.buildCoverageReport('', root);
    expect(empty['complete'], isFalse);
    expect(empty['sourceFiles'], 0);
  });

  for (final malformed in [
    'DA:1,1',
    'BRDA:1,0,0,1',
    'end_of_record',
    'SF:lib/main.dart\nSF:lib/main.dart',
    'SF:lib/main.dart\nDA:1,1',
    'SF:lib/main.dart\nDA:1\nend_of_record',
    'SF:lib/main.dart\nDA:1,1,a,b\nend_of_record',
    'SF:lib/main.dart\nDA:0,1\nend_of_record',
    'SF:lib/main.dart\nDA:-1,1\nend_of_record',
    'SF:lib/main.dart\nDA:1,NaN\nend_of_record',
    'SF:lib/main.dart\nBRDA:1,0,0\nend_of_record',
    'SF:lib/main.dart\nBRDA:1,-1,0,1\nend_of_record',
    'SF:lib/main.dart\nBRDA:1,0,no,1\nend_of_record',
  ]) {
    test('malformed counter input is rejected: $malformed', () {
      expect(
        () => coverage.buildCoverageReport(malformed, root),
        throwsFormatException,
      );
    });
  }

  test('CLI writes machine-readable and complete Markdown inventories', () {
    lcov.writeAsStringSync(record('lib/main.dart', hit));
    final result = coverage.runCoverageReport(
      [lcov.path, '--require-complete'],
      root: root,
      out: messages.add,
    );
    expect(result, 0);
    final report = jsonDecode(
      File.fromUri(root.uri.resolve('coverage/workspace-branches.json'))
          .readAsStringSync(),
    ) as Map;
    expect(report['complete'], isTrue);
    expect(
      File.fromUri(root.uri.resolve('coverage/workspace-branches.md'))
          .readAsStringSync(),
      contains('1/1'),
    );
    expect(messages.single, contains('complete: true'));
  });

  test(
    'CLI strict mode fails incomplete sources while report-only mode works',
    () {
      lcov.writeAsStringSync('');
      expect(
        coverage.runCoverageReport(
          [lcov.path, '--require-complete'],
          root: root,
          out: messages.add,
        ),
        1,
      );
      expect(
        coverage.runCoverageReport([lcov.path], root: root, out: messages.add),
        0,
      );
    },
  );

  test('CLI argument failures do not write outputs', () {
    for (final args in <List<String>>[
      [],
      ['x', '--unknown'],
      ['x', 'y', 'z'],
    ]) {
      expect(
        coverage.runCoverageReport(args, root: root, out: messages.add),
        64,
      );
    }
    expect(
      Directory.fromUri(root.uri.resolve('coverage/')).existsSync(),
      isFalse,
    );
  });

  test(
    'missing, malformed or unwritable reports fail with useful diagnostics',
    () {
      expect(
        coverage.runCoverageReport([lcov.path], root: root, out: messages.add),
        65,
      );
      lcov.writeAsStringSync('DA:1,1');
      expect(
        coverage.runCoverageReport([lcov.path], root: root, out: messages.add),
        65,
      );
      expect(messages.last, startsWith('Invalid LCOV:'));
      lcov.writeAsStringSync(record('lib/main.dart', hit));
      File.fromUri(root.uri.resolve('coverage'))
          .writeAsStringSync('Not a directory.');
      expect(
        coverage.runCoverageReport([lcov.path], root: root, out: messages.add),
        65,
      );
    },
  );

  test('standalone entrypoint preserves CLI failure status', () {
    final previous = exitCode;
    try {
      coverage.main([]);
      expect(exitCode, 64);
    } finally {
      exitCode = previous;
    }
  });
}
