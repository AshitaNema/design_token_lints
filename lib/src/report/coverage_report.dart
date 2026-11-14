import '../config/config.dart';
import '../config/rule_id.dart';

/// How often a category of tokens is used compared with raw values.
final class CategoryStats {
  /// Creates statistics.
  const CategoryStats({required this.usages, required this.findings});

  /// References to tokens of the category (or uses of the replacement widgets).
  final int usages;

  /// Raw values (or raw widgets) that bypass the design system.
  final int findings;

  /// `usages + findings`.
  int get total => usages + findings;

  /// The share of design-system usages, `0` to `100`, or `null` if there is
  /// nothing to measure.
  double? get percent => total == 0 ? null : usages * 100 / total;

  /// Returns the sum of this and [other].
  CategoryStats operator +(CategoryStats other) => CategoryStats(
    usages: usages + other.usages,
    findings: findings + other.findings,
  );
}

/// One place that bypasses the design system.
final class ReportFinding {
  /// Creates a report finding.
  const ReportFinding({
    required this.rule,
    required this.line,
    required this.column,
    required this.message,
    this.suggestedToken,
    this.baselined = false,
  });

  /// The rule that produced it.
  final RuleId rule;

  /// One-based line.
  final int line;

  /// One-based column.
  final int column;

  /// The problem message.
  final String message;

  /// The best replacement, if there is one.
  final String? suggestedToken;

  /// Whether the finding is accepted by the baseline, so the plugin does not
  /// report it. It still counts as a raw value.
  final bool baselined;
}

/// The findings of one file.
final class FileReport {
  /// Creates a file report.
  const FileReport({required this.path, required this.findings});

  /// The path relative to the analyzed directory, using `/`.
  final String path;

  /// The findings, in source order.
  final List<ReportFinding> findings;
}

/// The design-system coverage of a project.
final class CoverageReport {
  /// Creates a report.
  const CoverageReport({
    required this.categories,
    required this.files,
    required this.filesAnalyzed,
    this.skippedTokens = 0,
    this.issues = const [],
  });

  /// Statistics per configured category.
  final Map<DesignCategory, CategoryStats> categories;

  /// Files that have at least one finding, most findings first.
  final List<FileReport> files;

  /// The number of Dart files that were checked.
  final int filesAnalyzed;

  /// Token members that could not be evaluated statically.
  final int skippedTokens;

  /// Warnings found in the configuration.
  final List<ConfigIssue> issues;

  /// The totals over all categories.
  CategoryStats get overall => categories.values.fold(
    const CategoryStats(usages: 0, findings: 0),
    (sum, stats) => sum + stats,
  );

  /// The overall coverage, weighted by the number of usages and findings.
  double? get overallPercent => overall.percent;

  /// The total number of findings.
  int get totalFindings => files.fold(0, (sum, f) => sum + f.findings.length);

  /// The number of findings accepted by a baseline.
  int get baselinedFindings => files.fold(
    0,
    (sum, f) => sum + f.findings.where((finding) => finding.baselined).length,
  );

  /// The number of findings per rule.
  Map<RuleId, int> get findingsByRule {
    final counts = <RuleId, int>{
      for (final category in categories.keys)
        for (final rule in RuleId.values)
          if (rule.category == category) rule: 0,
    };
    for (final file in files) {
      for (final finding in file.findings) {
        counts[finding.rule] = (counts[finding.rule] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// The number of files with findings of [rule].
  int filesWith(RuleId rule) =>
      files.where((file) => file.findings.any((f) => f.rule == rule)).length;
}
