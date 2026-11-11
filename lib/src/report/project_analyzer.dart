import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../config/config_loader.dart';
import '../config/package_locator.dart';
import '../config/rule_id.dart';
import '../detectors/detector.dart';
import '../detectors/detectors.dart';
import '../detectors/finding.dart';
import '../detectors/node_visitors.dart';
import '../rules/design_token_rule.dart';
import 'coverage_report.dart';
import 'usage_counter.dart';

/// The outcome of [ProjectAnalyzer.analyze].
final class AnalysisOutcome {
  /// Creates an outcome.
  const AnalysisOutcome({required this.report, required this.errors});

  /// The coverage report, or `null` if the configuration has errors.
  final CoverageReport? report;

  /// Configuration errors that prevented a report.
  final List<ConfigIssue> errors;
}

/// Runs the rule detectors over a project and measures coverage.
///
/// This is the engine behind `design_token_lints coverage`. It uses the same
/// detectors as the analyzer plugin.
final class ProjectAnalyzer {
  /// Creates an analyzer that reads through [provider].
  ProjectAnalyzer(this.provider, {ConfigLoader? loader})
    : _loader = loader ?? ConfigLoader();

  /// The file system to read.
  final ResourceProvider provider;

  final ConfigLoader _loader;

  /// Analyzes the Dart files under [root].
  ///
  /// Only [categories] are measured when it is given.
  Future<AnalysisOutcome> analyze(
    String root, {
    Set<DesignCategory>? categories,
  }) async {
    final context = provider.pathContext;
    final collection = AnalysisContextCollection(
      includedPaths: [root],
      resourceProvider: provider,
    );

    final stats = <DesignCategory, CategoryStats>{};
    final fileReports = <FileReport>[];
    final errors = <ConfigIssue>[];
    final warnings = <ConfigIssue>[];
    final seenProjects = <ProjectConfig>{};
    final detectorCache = <ProjectConfig, List<Detector>>{};
    var filesAnalyzed = 0;

    void note(ProjectConfig project) {
      if (!seenProjects.add(project)) return;
      for (final issue in project.issues) {
        (issue.severity == ConfigIssueSeverity.error ? errors : warnings).add(
          issue,
        );
      }
    }

    for (final analysisContext in collection.contexts) {
      final paths =
          analysisContext.contextRoot
              .analyzedFiles()
              .where((path) => path.endsWith('.dart'))
              .toList()
            ..sort();
      for (final path in paths) {
        final file = provider.getFile(path);
        final lookup = _loader.lookup(file);
        final project = lookup.project;
        note(project);
        if (!project.isActive) continue;

        final active = {
          for (final category in DesignCategory.values)
            if (project.isRuleActive(_ruleOf(category)) &&
                (categories == null || categories.contains(category)))
              category,
        };
        if (active.isEmpty) continue;
        for (final category in active) {
          stats.putIfAbsent(
            category,
            () => const CategoryStats(usages: 0, findings: 0),
          );
        }

        final result = await analysisContext.currentSession.getResolvedUnit(
          path,
        );
        if (result is! ResolvedUnitResult) continue;
        final exemption = project.exemptionFor(
          path,
          packageName: lookup.packageName,
          content: result.content,
        );
        if (exemption != null) continue;

        final detectors = [
          for (final detector in detectorCache.putIfAbsent(
            project,
            () => Detectors.active(project),
          ))
            if (active.contains(detector.rule.category) &&
                project.exemptionFor(
                      path,
                      packageName: lookup.packageName,
                      content: result.content,
                      rule: detector.rule,
                    ) ==
                    null)
              detector,
        ];
        filesAnalyzed++;

        final findings = <Finding>[];
        result.unit.accept(DetectorWalker(detectors, findings.add));
        final counter = UsageCounter(project, active);
        result.unit.accept(counter);

        for (final category in active) {
          stats[category] =
              stats[category]! +
              CategoryStats(
                usages: counter.counts[category] ?? 0,
                findings: findings
                    .where((f) => f.rule.category == category)
                    .length,
              );
        }
        if (findings.isNotEmpty) {
          findings.sort((a, b) => a.offset.compareTo(b.offset));
          fileReports.add(
            FileReport(
              path: p.posix.joinAll(
                context.split(context.relative(path, from: root)),
              ),
              findings: [
                for (final finding in findings)
                  _toReportFinding(finding, result),
              ],
            ),
          );
        }
      }
    }

    if (errors.isNotEmpty) {
      return AnalysisOutcome(report: null, errors: errors);
    }
    fileReports.sort((a, b) {
      final byCount = b.findings.length.compareTo(a.findings.length);
      return byCount != 0 ? byCount : a.path.compareTo(b.path);
    });
    final ordered = {
      for (final category in DesignCategory.values)
        if (stats.containsKey(category)) category: stats[category]!,
    };
    return AnalysisOutcome(
      report: CoverageReport(
        categories: ordered,
        files: fileReports,
        filesAnalyzed: filesAnalyzed,
        skippedTokens: seenProjects.fold(
          0,
          (sum, project) => sum + project.index.skipped.length,
        ),
        issues: warnings,
      ),
      errors: const [],
    );
  }

  static RuleId _ruleOf(DesignCategory category) =>
      RuleId.values.firstWhere((rule) => rule.category == category);

  static ReportFinding _toReportFinding(
    Finding finding,
    ResolvedUnitResult result,
  ) {
    final location = result.lineInfo.getLocation(finding.offset);
    return ReportFinding(
      rule: finding.rule,
      line: location.lineNumber,
      column: location.columnNumber,
      message: DtlCodes.of(
        finding.rule,
      ).problemMessage.replaceAll('{0}', finding.raw),
      suggestedToken: finding.best?.reference,
    );
  }

  /// Finds the directory whose configuration applies to [start], for
  /// `check-config`.
  ProjectConfig? projectFor(Folder start) {
    final package = PackageLocator.nearest(start);
    if (package == null) return null;
    var project = _loader.load(package.root);
    if (!project.isActive) {
      final workspace = PackageLocator.workspaceRootOf(package);
      if (workspace != null) {
        final candidate = _loader.load(workspace.root);
        if (candidate.isActive) project = candidate;
      }
    }
    return project;
  }
}
