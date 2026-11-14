import 'dart:io';

import 'package:analyzer/file_system/file_system.dart' show ResourceProvider;
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../config/rule_id.dart';
import '../fixes/bulk_fixer.dart';
import '../report/baseline_writer.dart';
import '../report/project_analyzer.dart';
import '../report/renderers.dart';
import '../tokens/token_value.dart';

/// The exit codes of the command line tool.
abstract final class ExitCodes {
  /// Success.
  static const int ok = 0;

  /// Coverage is below `--fail-under`, or `fix --dry-run` found something
  /// to fix.
  static const int belowThreshold = 1;

  /// Invalid usage, or the configuration has errors.
  static const int usage = 2;
}

/// Runs the command line tool.
///
/// [out] and [err] default to stdout and stderr; [provider] and
/// [workingDirectory] default to the real file system and the current
/// directory. Returns the exit code.
Future<int> runCli(
  List<String> arguments, {
  StringSink? out,
  StringSink? err,
  ResourceProvider? provider,
  String? workingDirectory,
}) async {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;
  final resources = provider ?? PhysicalResourceProvider.INSTANCE;
  final cwd = workingDirectory ?? Directory.current.path;

  final parser = _buildParser();
  final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (error) {
    stderrSink
      ..writeln(error.message)
      ..writeln()
      ..write(_usage(parser));
    return ExitCodes.usage;
  }

  if (results['help'] == true && results.command == null) {
    stdoutSink.write(_usage(parser));
    return ExitCodes.ok;
  }
  final command = results.command;
  if (command == null) {
    stderrSink.write(_usage(parser));
    return ExitCodes.usage;
  }
  if (command['help'] == true) {
    stdoutSink.write(_commandUsage(command.name!, parser));
    return ExitCodes.ok;
  }

  final rest = command.rest;
  if (rest.length > 1) {
    stderrSink.writeln('Expected at most one path, got ${rest.length}.');
    return ExitCodes.usage;
  }
  final root = p.normalize(
    p.isAbsolute(rest.isEmpty ? '.' : rest.single)
        ? rest.isEmpty
              ? '.'
              : rest.single
        : p.join(cwd, rest.isEmpty ? '.' : rest.single),
  );
  if (!resources.getFolder(root).exists) {
    stderrSink.writeln('"$root" is not a directory.');
    return ExitCodes.usage;
  }

  return switch (command.name) {
    'coverage' => _coverage(command, root, resources, stdoutSink, stderrSink),
    'fix' => _fix(command, root, resources, stdoutSink, stderrSink),
    'baseline' => _baseline(root, resources, stdoutSink, stderrSink),
    _ => _checkConfig(root, resources, stdoutSink, stderrSink),
  };
}

ArgParser _buildParser() {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');
  parser.addCommand('coverage')
    ..addOption(
      'format',
      abbr: 'f',
      allowed: ReportFormat.values.map((f) => f.name),
      defaultsTo: ReportFormat.console.name,
      help: 'The output format.',
    )
    ..addOption('output', abbr: 'o', help: 'Write the report to a file.')
    ..addOption(
      'fail-under',
      help: 'Exit with code 1 when overall coverage is below this percentage.',
      valueHelp: '80',
    )
    ..addOption(
      'category',
      help:
          'Only measure these categories, comma-separated: '
          '${DesignCategory.values.map((c) => c.key).join(', ')}.',
      valueHelp: 'color,spacing',
    )
    ..addFlag('help', abbr: 'h', negatable: false);
  parser.addCommand('fix')
    ..addFlag(
      'dry-run',
      negatable: false,
      help:
          'List the fixes without changing any file. Exits with code 1 when '
          'there is something to fix.',
    )
    ..addOption(
      'rule',
      help:
          'Only fix these rules, comma-separated: '
          '${RuleId.values.map((r) => r.code).join(', ')}.',
      valueHelp: 'avoid_raw_color',
    )
    ..addFlag('help', abbr: 'h', negatable: false);
  parser.addCommand('baseline').addFlag('help', abbr: 'h', negatable: false);
  parser
      .addCommand('check-config')
      .addFlag('help', abbr: 'h', negatable: false);
  return parser;
}

String _usage(ArgParser parser) =>
    'Measures and checks design-system adoption.\n'
    '\n'
    'Usage: design_token_lints <command> [path]\n'
    '\n'
    'Commands:\n'
    '  coverage       Measure how much of the UI uses the design system.\n'
    '  fix            Replace raw values that match exactly one token.\n'
    '  baseline       Accept the current raw values; report only new ones.\n'
    '  check-config   Validate the configuration and print the tokens found.\n'
    '\n'
    'Run "design_token_lints <command> --help" for the options of a command.\n';

String _commandUsage(String name, ArgParser parser) {
  final command = parser.commands[name]!;
  return 'Usage: design_token_lints $name [path]\n\n${command.usage}\n';
}

Future<int> _coverage(
  ArgResults command,
  String root,
  ResourceProvider provider,
  StringSink out,
  StringSink err,
) async {
  final format = ReportFormat.fromName(command['format'] as String)!;

  double? failUnder;
  final failUnderOption = command['fail-under'] as String?;
  if (failUnderOption != null) {
    failUnder = double.tryParse(failUnderOption);
    if (failUnder == null || failUnder < 0 || failUnder > 100) {
      err.writeln('--fail-under must be a number between 0 and 100.');
      return ExitCodes.usage;
    }
  }

  Set<DesignCategory>? categories;
  final categoryOption = command['category'] as String?;
  if (categoryOption != null) {
    categories = {};
    for (final name in categoryOption.split(',')) {
      final category = DesignCategory.fromKey(name.trim());
      if (category == null) {
        err.writeln(
          'Unknown category "${name.trim()}". Expected one of '
          '${DesignCategory.values.map((c) => c.key).join(', ')}.',
        );
        return ExitCodes.usage;
      }
      categories.add(category);
    }
  }

  final outcome = await ProjectAnalyzer(
    provider,
  ).analyze(root, categories: categories);
  final report = outcome.report;
  if (report == null) {
    for (final issue in outcome.errors) {
      err.writeln('${issue.severity.name}: ${issue.message}');
    }
    err.writeln('Run "design_token_lints check-config" for details.');
    return ExitCodes.usage;
  }
  if (report.categories.isEmpty) {
    err.writeln(
      'No design_token_lints configuration found for "$root". Add a '
      '`design_token_lints:` section to analysis_options.yaml or create '
      'design_token_lints.yaml.',
    );
    return ExitCodes.usage;
  }
  for (final issue in report.issues) {
    err.writeln('${issue.severity.name}: ${issue.message}');
  }

  final rendered = renderReport(report, format);
  final outputPath = command['output'] as String?;
  if (outputPath == null) {
    out.write(rendered);
  } else {
    final file = File(
      p.isAbsolute(outputPath) ? outputPath : p.join(root, outputPath),
    );
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(rendered);
    out.writeln(summaryLine(report));
  }

  final overall = report.overallPercent;
  if (failUnder != null && overall != null && overall < failUnder) {
    err.writeln(
      'Coverage ${overall.toStringAsFixed(1)}% is below the required '
      '${failUnder.toStringAsFixed(failUnder % 1 == 0 ? 0 : 1)}%.',
    );
    return ExitCodes.belowThreshold;
  }
  return ExitCodes.ok;
}

Future<int> _fix(
  ArgResults command,
  String root,
  ResourceProvider provider,
  StringSink out,
  StringSink err,
) async {
  final dryRun = command['dry-run'] == true;
  Set<RuleId>? rules;
  final ruleOption = command['rule'] as String?;
  if (ruleOption != null) {
    rules = {};
    for (final name in ruleOption.split(',')) {
      final rule = RuleId.values.where((r) => r.code == name.trim());
      if (rule.isEmpty) {
        err.writeln(
          'Unknown rule "${name.trim()}". Expected one of '
          '${RuleId.values.map((r) => r.code).join(', ')}.',
        );
        return ExitCodes.usage;
      }
      rules.add(rule.single);
    }
  }

  final outcome = await BulkFixer(
    provider,
  ).fix(root, rules: rules, dryRun: dryRun);
  if (outcome.errors.isNotEmpty) {
    for (final issue in outcome.errors) {
      err.writeln('${issue.severity.name}: ${issue.message}');
    }
    err.writeln('Nothing was changed. Run "design_token_lints check-config".');
    return ExitCodes.usage;
  }
  if (!outcome.configured) {
    err.writeln(
      'No design_token_lints configuration found for "$root". Add a '
      '`design_token_lints:` section to analysis_options.yaml or create '
      'design_token_lints.yaml.',
    );
    return ExitCodes.usage;
  }
  for (final issue in outcome.warnings) {
    err.writeln('${issue.severity.name}: ${issue.message}');
  }

  String? lastPath;
  for (final fix in outcome.applied) {
    if (fix.path != lastPath) {
      if (lastPath != null) out.writeln();
      out.writeln(fix.path);
      lastPath = fix.path;
    }
    out.writeln(
      '  ${fix.line}:${fix.column}  ${_short(fix.raw)} -> ${fix.replacement}',
    );
  }
  if (outcome.applied.isNotEmpty) out.writeln();

  final count = outcome.applied.length;
  final files = outcome.fileCount;
  final summary =
      '$count ${count == 1 ? 'issue' : 'issues'} in '
      '$files ${files == 1 ? 'file' : 'files'}';
  if (count == 0) {
    out.writeln('Nothing to fix.');
  } else if (dryRun) {
    out.writeln('Would fix $summary. Run without --dry-run to apply.');
  } else {
    out.writeln('Fixed $summary. Run "dart format" if any line got too long.');
  }

  void listSkipped(SkipReason reason, String heading) {
    final skipped = outcome.skipped.where((s) => s.reason == reason).toList();
    if (skipped.isEmpty) return;
    out
      ..writeln()
      ..writeln(heading);
    for (final s in skipped) {
      out.writeln(
        '  ${s.path}:${s.line}:${s.column}  ${_short(s.raw)}: '
        '${s.candidates.join(', ')}',
      );
    }
  }

  listSkipped(
    SkipReason.ambiguous,
    'Not fixed, more than one token matches (choose one in your IDE):',
  );
  listSkipped(
    SkipReason.overlap,
    'Not fixed, inside another fix (run the command again):',
  );
  final left = outcome.withoutExactToken;
  if (left > 0) {
    out
      ..writeln()
      ..writeln(
        '$left ${left == 1 ? 'issue has' : 'issues have'} no exact token; '
        '"dart analyze" lists them.',
      );
  }
  return dryRun && count > 0 ? ExitCodes.belowThreshold : ExitCodes.ok;
}

Future<int> _baseline(
  String root,
  ResourceProvider provider,
  StringSink out,
  StringSink err,
) async {
  final outcome = await BaselineWriter(provider).write(root);
  if (outcome.errors.isNotEmpty) {
    for (final issue in outcome.errors) {
      err.writeln('${issue.severity.name}: ${issue.message}');
    }
    err.writeln('Nothing was written. Run "design_token_lints check-config".');
    return ExitCodes.usage;
  }
  if (outcome.written.isEmpty) {
    err.writeln(
      'No design_token_lints configuration found for "$root". Add a '
      '`design_token_lints:` section to analysis_options.yaml or create '
      'design_token_lints.yaml.',
    );
    return ExitCodes.usage;
  }
  for (final issue in outcome.warnings) {
    err.writeln('${issue.severity.name}: ${issue.message}');
  }
  for (final written in outcome.written) {
    final shown = p.relative(written.path, from: root);
    out.writeln(
      'Wrote $shown: ${written.findings} raw '
      '${written.findings == 1 ? 'value' : 'values'} in ${written.files} '
      '${written.files == 1 ? 'file' : 'files'}.',
    );
  }
  out
    ..writeln()
    ..writeln(
      'These are no longer reported; new raw values are. Commit the file, '
      'and run the command again after fixing some to shrink it.',
    );
  return ExitCodes.ok;
}

/// [raw] on one line, shortened to 40 characters.
String _short(String raw) {
  final flat = raw.replaceAll(RegExp(r'\s+'), ' ');
  return flat.length <= 40 ? flat : '${flat.substring(0, 39)}…';
}

int _checkConfig(
  String root,
  ResourceProvider provider,
  StringSink out,
  StringSink err,
) {
  final project = ProjectAnalyzer(
    provider,
  ).projectFor(provider.getFolder(root));
  if (project == null || !project.config.isPresent) {
    final errors = project?.config.issues ?? const [];
    for (final issue in errors) {
      err.writeln('${issue.severity.name}: ${issue.message}');
    }
    err.writeln(
      'No design_token_lints configuration found for "$root". Add a '
      '`design_token_lints:` section to analysis_options.yaml or create '
      'design_token_lints.yaml next to pubspec.yaml.',
    );
    return ExitCodes.usage;
  }

  final config = project.config;
  final index = project.index;
  final context = provider.pathContext;
  String relative(String path) => p.posix.joinAll(
    context.split(context.relative(path, from: config.rootPath)),
  );

  out.writeln(
    'Configuration: ${switch (config.source) {
      ConfigSource.standalone => 'design_token_lints.yaml',
      ConfigSource.analysisOptions => 'analysis_options.yaml',
      ConfigSource.none => 'none',
    }} (${relative(config.rootPath) == '.' ? '.' : relative(config.rootPath)})',
  );
  out.writeln();

  for (final MapEntry(key: category, value: source) in config.tokens.entries) {
    final entries = index.of(category);
    final found = index.hasCategory(category);
    out.writeln(
      '${category.key}: ${source.className} (${source.file}) — '
      '${found ? '${entries.length} '
                '${entries.length == 1 ? 'token' : 'tokens'}' : 'not found'}',
    );
    for (final entry in entries) {
      out.writeln('  ${entry.reference} = ${_describe(entry.value)}');
    }
    for (final skipped in index.skipped.where((s) => s.category == category)) {
      out.writeln('  skipped ${skipped.reference}: ${skipped.reason}');
    }
  }
  if (config.components.isNotEmpty) {
    out.writeln('components:');
    for (final MapEntry(key: raw, value: component)
        in config.components.entries) {
      out.writeln(
        '  $raw -> ${component.replacement}'
        '${component.import == null ? '' : ' (${component.import})'}',
      );
    }
  }

  final issues = project.issues;
  if (issues.isNotEmpty) {
    out
      ..writeln()
      ..writeln('Problems:');
    for (final issue in issues) {
      out.writeln('  ${issue.severity.name}: ${issue.message}');
    }
  }
  return project.issues.any((i) => i.severity == ConfigIssueSeverity.error)
      ? ExitCodes.usage
      : ExitCodes.ok;
}

String _num(double value) =>
    value == value.truncateToDouble() ? '${value.toInt()}' : '$value';

String _describe(TokenValue value) => switch (value) {
  NumberValue() => _num(value.value),
  ColorValue() =>
    '0x${value.argb.toRadixString(16).toUpperCase().padLeft(8, '0')}',
  RadiusValue() => 'Radius.circular(${_num(value.value)})',
  BorderRadiusValue() => 'BorderRadius.circular(${_num(value.value)})',
  TextStyleValue() =>
    'TextStyle(${[if (value.fontSize != null) 'fontSize: ${_num(value.fontSize!)}', if (value.fontWeight != null) 'fontWeight: ${value.fontWeight}', if (value.height != null) 'height: ${_num(value.height!)}', if (value.letterSpacing != null) 'letterSpacing: ${_num(value.letterSpacing!)}'].join(', ')})',
  ShadowValue() =>
    '${value.isList ? 'List<BoxShadow>' : 'BoxShadow'}(${value.layers.length} '
        '${value.layers.length == 1 ? 'layer' : 'layers'})',
};
