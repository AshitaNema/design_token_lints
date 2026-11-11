import 'dart:convert';

import '../config/rule_id.dart';
import 'coverage_report.dart';

/// The output formats of the coverage command.
enum ReportFormat {
  /// Human-readable text for a terminal.
  console,

  /// Machine-readable JSON with a `schemaVersion`.
  json,

  /// A compact Markdown summary, suitable for a pull-request comment.
  markdown;

  /// Looks up a format by name.
  static ReportFormat? fromName(String name) {
    for (final format in values) {
      if (format.name == name) return format;
    }
    return null;
  }
}

/// The version of the JSON report layout.
const int jsonSchemaVersion = 1;

/// The hidden comment that identifies the Markdown report, so a CI step can
/// update a single "sticky" pull-request comment.
const String markdownMarker = '<!-- design-token-lints -->';

/// Renders [report] in [format].
String renderReport(CoverageReport report, ReportFormat format) =>
    switch (format) {
      ReportFormat.console => renderConsole(report),
      ReportFormat.json => renderJson(report),
      ReportFormat.markdown => renderMarkdown(report),
    };

String _label(DesignCategory category) => switch (category) {
  DesignCategory.color => 'colors',
  DesignCategory.spacing => 'spacing',
  DesignCategory.radius => 'radius',
  DesignCategory.typography => 'typography',
  DesignCategory.shadow => 'shadows',
  DesignCategory.component => 'components',
};

String _rawNoun(RuleId rule, int count) {
  final one = count == 1;
  return switch (rule) {
    RuleId.avoidRawColor => one ? 'raw color' : 'raw colors',
    RuleId.avoidMagicSpacing =>
      one ? 'magic spacing value' : 'magic spacing values',
    RuleId.avoidRawRadius => one ? 'raw radius' : 'raw radii',
    RuleId.avoidInlineTextStyle =>
      one ? 'inline text style' : 'inline text styles',
    RuleId.avoidRawShadow => one ? 'raw shadow' : 'raw shadows',
    RuleId.preferDesignSystemComponent =>
      one ? 'off-system widget' : 'off-system widgets',
  };
}

String _percent(double? value) => value == null ? 'n/a' : '${value.round()}%';

String _plural(int count, String one, String many) => count == 1 ? one : many;

/// The one-line summary used by the console output.
String summaryLine(CoverageReport report) {
  final parts = [
    for (final MapEntry(key: category, value: stats)
        in report.categories.entries)
      '${_label(category)} ${_percent(stats.percent)}',
  ];
  final buffer = StringBuffer(
    'Design system coverage: ${_percent(report.overallPercent)}',
  );
  if (parts.isNotEmpty) buffer.write(' (${parts.join(', ')})');
  final worst = _largestRule(report);
  if (worst == null) {
    buffer.write(' — no raw values found');
  } else {
    final count = report.findingsByRule[worst]!;
    final files = report.filesWith(worst);
    buffer.write(
      ' — $count ${_rawNoun(worst, count)} in $files '
      '${_plural(files, 'file', 'files')}',
    );
  }
  return buffer.toString();
}

RuleId? _largestRule(CoverageReport report) {
  RuleId? best;
  var bestCount = 0;
  for (final MapEntry(key: rule, value: count)
      in report.findingsByRule.entries) {
    if (count > bestCount) {
      best = rule;
      bestCount = count;
    }
  }
  return best;
}

/// Renders [report] for a terminal.
String renderConsole(CoverageReport report) {
  final out = StringBuffer(summaryLine(report))..writeln();
  if (report.categories.isEmpty) return out.toString();

  out
    ..writeln()
    ..writeln('  Category     Coverage  Token uses  Raw values');
  for (final MapEntry(key: category, value: stats)
      in report.categories.entries) {
    out.writeln(
      '  ${_label(category).padRight(12)} '
      '${_percent(stats.percent).padRight(9)} '
      '${'${stats.usages}'.padRight(11)} '
      '${stats.findings}',
    );
  }
  final overall = report.overall;
  out.writeln(
    '  ${'overall'.padRight(12)} '
    '${_percent(overall.percent).padRight(9)} '
    '${'${overall.usages}'.padRight(11)} '
    '${overall.findings}',
  );

  if (report.files.isNotEmpty) {
    out
      ..writeln()
      ..writeln('Files with the most raw values:');
    for (final file in report.files.take(5)) {
      out.writeln('  ${file.path} (${file.findings.length})');
    }
  }
  out
    ..writeln()
    ..write(
      '${report.filesAnalyzed} ${_plural(report.filesAnalyzed, 'file', 'files')} '
      'checked',
    );
  if (report.skippedTokens > 0) {
    out.write(
      ', ${report.skippedTokens} token '
      '${_plural(report.skippedTokens, 'member', 'members')} '
      'could not be evaluated',
    );
  }
  out.writeln('.');
  return out.toString();
}

/// Renders [report] as JSON.
String renderJson(CoverageReport report) {
  double? round(double? value) =>
      value == null ? null : (value * 10).round() / 10;
  Map<String, Object?> stats(CategoryStats s) => {
    'percent': round(s.percent),
    'usages': s.usages,
    'findings': s.findings,
  };
  final document = <String, Object?>{
    'schemaVersion': jsonSchemaVersion,
    'filesAnalyzed': report.filesAnalyzed,
    'skippedTokens': report.skippedTokens,
    'totals': stats(report.overall),
    'categories': {
      for (final MapEntry(key: category, value: s) in report.categories.entries)
        category.key: stats(s),
    },
    'rules': {
      for (final MapEntry(key: rule, value: count)
          in report.findingsByRule.entries)
        rule.code: count,
    },
    'files': [
      for (final file in report.files)
        {
          'path': file.path,
          'findings': [
            for (final finding in file.findings)
              {
                'rule': finding.rule.code,
                'line': finding.line,
                'column': finding.column,
                'message': finding.message,
                'suggestedToken': finding.suggestedToken,
              },
          ],
        },
    ],
  };
  return '${const JsonEncoder.withIndent('  ').convert(document)}\n';
}

/// Renders [report] as Markdown.
String renderMarkdown(CoverageReport report) {
  final out = StringBuffer()
    ..writeln(markdownMarker)
    ..writeln('### Design system coverage: ${_percent(report.overallPercent)}')
    ..writeln();
  if (report.categories.isEmpty) {
    out.writeln('No token categories are configured.');
    return out.toString();
  }
  out
    ..writeln('| Category | Coverage | Token uses | Raw values |')
    ..writeln('| --- | ---: | ---: | ---: |');
  for (final MapEntry(key: category, value: stats)
      in report.categories.entries) {
    out.writeln(
      '| ${_label(category)} | ${_percent(stats.percent)} | '
      '${stats.usages} | ${stats.findings} |',
    );
  }
  final overall = report.overall;
  out.writeln(
    '| **overall** | **${_percent(overall.percent)}** | '
    '**${overall.usages}** | **${overall.findings}** |',
  );
  if (report.files.isNotEmpty) {
    out
      ..writeln()
      ..writeln('**Files with the most raw values**')
      ..writeln()
      ..writeln('| File | Raw values |')
      ..writeln('| --- | ---: |');
    for (final file in report.files.take(10)) {
      out.writeln('| `${file.path}` | ${file.findings.length} |');
    }
  }
  out
    ..writeln()
    ..writeln(
      '<sub>${report.filesAnalyzed} '
      '${_plural(report.filesAnalyzed, 'file', 'files')} checked.</sub>',
    );
  return out.toString();
}
