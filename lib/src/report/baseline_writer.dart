import 'package:analyzer/file_system/file_system.dart';
import 'package:path/path.dart' as p;

import '../config/baseline.dart';
import '../config/config.dart';
import '../config/config_loader.dart';
import '../config/package_locator.dart';
import '../detectors/finding.dart';
import 'project_analyzer.dart';

/// A baseline file written by [BaselineWriter].
final class WrittenBaseline {
  /// Creates a record of a written baseline.
  const WrittenBaseline({
    required this.path,
    required this.findings,
    required this.files,
  });

  /// The absolute path of the baseline file.
  final String path;

  /// The number of accepted findings.
  final int findings;

  /// The number of files with accepted findings.
  final int files;
}

/// The result of [BaselineWriter.write].
final class BaselineOutcome {
  /// Creates an outcome.
  const BaselineOutcome({
    required this.written,
    required this.errors,
    required this.warnings,
  });

  /// One entry per configuration whose baseline was written.
  final List<WrittenBaseline> written;

  /// Configuration errors. Nothing is written when there are any.
  final List<ConfigIssue> errors;

  /// Configuration warnings.
  final List<ConfigIssue> warnings;
}

/// Records the current findings of a project in its baseline file.
///
/// This is the engine behind `design_token_lints baseline`. Every finding is
/// recorded, including ones silenced by `// ignore:` comments, because the
/// plugin matches the baseline before the analysis server applies those
/// comments. Entries for files outside the analyzed directory are kept.
final class BaselineWriter {
  /// Creates a writer that reads and writes through [provider].
  BaselineWriter(this.provider, {ConfigLoader? loader})
    : _analyzer = ProjectAnalyzer(provider, loader: loader);

  /// The file system to read and write.
  final ResourceProvider provider;

  final ProjectAnalyzer _analyzer;

  /// Analyzes [root] and writes the baseline of every configuration found.
  Future<BaselineOutcome> write(String root) async {
    final found = <ProjectConfig, Map<String, List<Finding>>>{};
    final walk = await _analyzer.walkFiles(
      root,
      onFile: (visit) {
        final byFile = found.putIfAbsent(visit.project, () => {});
        final findings = visit.findings();
        if (findings.isNotEmpty) {
          byFile[visit.project.relativePath(visit.path)] = findings;
        }
      },
    );
    if (walk.errors.isNotEmpty) {
      return BaselineOutcome(
        written: const [],
        errors: walk.errors,
        warnings: walk.warnings,
      );
    }

    // A configuration whose files are all clean still gets its baseline
    // rewritten, so stale entries go away.
    for (final project in walk.projects) {
      if (project.isActive) found.putIfAbsent(project, () => {});
    }

    final context = provider.pathContext;
    final written = <WrittenBaseline>[];
    for (final MapEntry(key: project, value: byFile) in found.entries) {
      final configRoot = project.config.rootPath;
      bool outsideRoot(String relativePath) {
        final absolute = context.joinAll([
          configRoot,
          ...p.posix.split(relativePath),
        ]);
        return !context.isWithin(root, absolute) &&
            !context.equals(root, absolute);
      }

      final baseline = project.baseline.mergedWith(
        Baseline.of(byFile),
        outsideRoot,
      );
      final file = childFile(provider.getFolder(configRoot), baselineFileName);
      file.writeAsStringSync(baseline.serialize());
      written.add(
        WrittenBaseline(
          path: file.path,
          findings: baseline.total,
          files: baseline.paths.length,
        ),
      );
    }
    written.sort((a, b) => a.path.compareTo(b.path));
    return BaselineOutcome(
      written: written,
      errors: const [],
      warnings: walk.warnings,
    );
  }
}
