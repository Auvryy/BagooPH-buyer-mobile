import 'dart:convert';
import 'dart:io';

class SourceCoverage {
  bool observed = false;
  final lines = <int, int>{};
  final branches = <String, int>{};

  Map<String, Object> toJson() => {
    'observed': observed,
    'linesFound': lines.length,
    'linesHit': lines.values.where((hits) => hits > 0).length,
    'branchesFound': branches.length,
    'branchesHit': branches.values.where((hits) => hits > 0).length,
    'uncoveredLines': [
      for (final entry in lines.entries)
        if (entry.value == 0) entry.key,
    ],
    'uncoveredBranches': [
      for (final entry in branches.entries)
        if (entry.value == 0) entry.key,
    ],
  };
}

/// Reports actual LCOV counters and separately exposes unmeasured source files.
/// An absent source file must never disappear from the completeness gate.
Map<String, Object?> buildCoverageReport(String lcov, Directory root) {
  final sources = <String, SourceCoverage>{};
  for (final name in ['lib', 'tool', 'e2e']) {
    final directory = Directory.fromUri(root.uri.resolve('$name/'));
    if (!directory.existsSync()) continue;
    final paths =
        directory
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .map(
              (file) =>
                  file.uri.toString().substring(root.uri.toString().length),
            )
            .toList()
          ..sort();
    for (final path in paths) {
      sources[path] = SourceCoverage();
    }
  }
  SourceCoverage? current;
  var recordOpen = false;
  int nonnegative(String value) {
    final number = int.tryParse(value);
    if (number == null || number < 0) {
      throw const FormatException('Invalid LCOV counter.');
    }
    return number;
  }

  for (final line in const LineSplitter().convert(lcov)) {
    if (line.startsWith('SF:')) {
      if (recordOpen) throw const FormatException('Unterminated LCOV record.');
      final uri = root.uri.resolve(line.substring(3));
      final prefix = root.uri.toString();
      final path = uri.toString();
      current = path.startsWith(prefix)
          ? sources[path.substring(prefix.length)]
          : null;
      recordOpen = true;
    } else if (line == 'end_of_record') {
      if (!recordOpen) throw const FormatException('Unexpected LCOV end.');
      recordOpen = false;
      current = null;
    } else if (line.startsWith('DA:') || line.startsWith('BRDA:')) {
      if (!recordOpen) {
        throw const FormatException('LCOV counter without file.');
      }
      final branch = line.startsWith('BRDA:');
      final parts = line.substring(branch ? 5 : 3).split(',');
      if ((branch && parts.length != 4) ||
          (!branch && (parts.length < 2 || parts.length > 3))) {
        throw const FormatException('Invalid LCOV counter fields.');
      }
      final sourceLine = nonnegative(parts[0]);
      if (sourceLine == 0) throw const FormatException('Invalid source line.');
      final hit = branch && parts[3] == '-'
          ? 0
          : nonnegative(parts[branch ? 3 : 1]);
      current?.observed = true;
      if (branch) {
        final block = nonnegative(parts[1]);
        final branchNumber = nonnegative(parts[2]);
        final key = '$sourceLine:$block:$branchNumber';
        final previous = current?.branches[key] ?? 0;
        if (current != null) {
          current.branches[key] = hit > previous ? hit : previous;
        }
      } else {
        final previous = current?.lines[sourceLine] ?? 0;
        if (current != null) {
          current.lines[sourceLine] = hit > previous ? hit : previous;
        }
      }
    }
  }
  if (recordOpen) throw const FormatException('Unterminated LCOV record.');
  final branchTotal = sources.values.fold(
    0,
    (n, file) => n + file.branches.length,
  );
  final branchHit = sources.values.fold(
    0,
    (n, file) => n + file.branches.values.where((hits) => hits > 0).length,
  );
  final missing = [
    for (final entry in sources.entries)
      if (!entry.value.observed) entry.key,
  ];
  return {
    'scope': 'All Dart source files under lib/, tool/, and e2e/',
    'counterMeaning': 'Flutter/Dart LCOV BRDA counters; not a claim about uninstrumented native code or every boolean alternative.',
    'sourceFiles': sources.length,
    'measuredFiles': sources.length - missing.length,
    'unmeasuredFiles': missing,
    'branchesFound': branchTotal,
    'branchesHit': branchHit,
    'branchPercent': branchTotal == 0 ? null : branchHit * 100 / branchTotal,
    'complete':
        sources.isNotEmpty &&
        missing.isEmpty &&
        branchTotal > 0 &&
        branchHit == branchTotal,
    'files': {
      for (final entry in sources.entries) entry.key: entry.value.toJson(),
    },
  };
}

String coverageMarkdown(Map<String, Object?> report) {
  final output = StringBuffer('# Buyer Dart coverage inventory\n\n')
    ..writeln(report['scope'])
    ..writeln('\n${report['counterMeaning']}\n')
    ..writeln(
      'Measured files: ${report['measuredFiles']}/${report['sourceFiles']}.',
    )
    ..writeln(
      'Reported branch counters: ${report['branchesHit']}/${report['branchesFound']}.',
    )
    ..writeln('100% completeness gate: ${report['complete']}.\n')
    ..writeln(
      '| Source | Measured | Branches hit/found | Uncovered branch keys (line:block:branch) |',
    )
    ..writeln('| --- | --- | --- | --- |');
  final files = report['files'] as Map<String, Map<String, Object>>;
  for (final entry in files.entries) {
    final file = entry.value;
    output.writeln(
      '| ${entry.key} | ${file['observed']} | ${file['branchesHit']}/${file['branchesFound']} | ${(file['uncoveredBranches'] as List).join(', ')} |',
    );
  }
  return output.toString();
}

int runCoverageReport(
  List<String> args, {
  Directory? root,
  void Function(String)? out,
}) {
  final write = out ?? stdout.writeln;
  if (args.isEmpty) {
    write(
      'Usage: dart run tool/testing/coverage_report.dart <LCOV> [--require-complete]',
    );
    return 64;
  }
  if (args.length > 2 ||
      (args.length == 2 && args[1] != '--require-complete')) {
    write('Unknown coverage report option.');
    return 64;
  }
  try {
    final workspace = root ?? Directory.current;
    final report = buildCoverageReport(
      File(args.first).readAsStringSync(),
      workspace,
    );
    final destination = Directory.fromUri(workspace.uri.resolve('coverage/'))
      ..createSync(recursive: true);
    File.fromUri(destination.uri.resolve('workspace-branches.json'))
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    File.fromUri(destination.uri.resolve('workspace-branches.md'))
        .writeAsStringSync(coverageMarkdown(report));
    write(
      'Branch counters: ${report['branchesHit']}/${report['branchesFound']}; measured files: ${report['measuredFiles']}/${report['sourceFiles']}; complete: ${report['complete']}',
    );
    return args.contains('--require-complete') && report['complete'] != true
        ? 1
        : 0;
  } on FileSystemException catch (_) {
    write('Cannot read LCOV or write coverage output.');
    return 65;
  } on FormatException catch (error) {
    write('Invalid LCOV: ${error.message}');
    return 65;
  }
}

void main(List<String> args) {
  exitCode = runCoverageReport(args);
}
