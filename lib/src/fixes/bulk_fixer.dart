import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../config/config_loader.dart';
import '../config/rule_id.dart';
import '../detectors/finding.dart';
import '../report/project_analyzer.dart';
import 'ignore_comments.dart';

/// A replacement made, or that would be made, by [BulkFixer].
final class AppliedFix {
  /// Creates a record of a fix.
  const AppliedFix({
    required this.path,
    required this.line,
    required this.column,
    required this.rule,
    required this.raw,
    required this.replacement,
  });

  /// The file, relative to the analyzed root, with `/` separators.
  final String path;

  /// The 1-based line of the replaced code.
  final int line;

  /// The 1-based column of the replaced code.
  final int column;

  /// The rule whose finding was fixed.
  final RuleId rule;

  /// The replaced source text.
  final String raw;

  /// The token reference that replaced it.
  final String replacement;
}

/// Why [BulkFixer] left a finding with an exact token alone.
enum SkipReason {
  /// More than one token has the same value; a person has to choose.
  ambiguous,

  /// The finding lies inside, or around, another fix in the same run.
  overlap,
}

/// A finding with an exact token that [BulkFixer] did not fix.
final class SkippedFix {
  /// Creates a record of a skipped finding.
  const SkippedFix({
    required this.path,
    required this.line,
    required this.column,
    required this.rule,
    required this.raw,
    required this.reason,
    required this.candidates,
  });

  /// The file, relative to the analyzed root, with `/` separators.
  final String path;

  /// The 1-based line of the finding.
  final int line;

  /// The 1-based column of the finding.
  final int column;

  /// The rule of the finding.
  final RuleId rule;

  /// The source text of the finding.
  final String raw;

  /// Why it was not fixed.
  final SkipReason reason;

  /// The tokens that match exactly.
  final List<String> candidates;
}

/// The result of [BulkFixer.fix].
final class FixOutcome {
  /// Creates an outcome.
  const FixOutcome({
    required this.applied,
    required this.skipped,
    required this.withoutExactToken,
    required this.configured,
    required this.errors,
    required this.warnings,
  });

  /// The fixes, in file and source order.
  final List<AppliedFix> applied;

  /// Findings with an exact token that were not fixed.
  final List<SkippedFix> skipped;

  /// Findings that have no exact token and were left for a person.
  final int withoutExactToken;

  /// Whether any configuration applied to the analyzed files.
  final bool configured;

  /// Configuration errors. Nothing is fixed when there are any.
  final List<ConfigIssue> errors;

  /// Configuration warnings.
  final List<ConfigIssue> warnings;

  /// The number of files with at least one fix.
  int get fileCount => {for (final fix in applied) fix.path}.length;
}

/// Applies every unambiguous exact-token fix in a project.
///
/// This is the engine behind `design_token_lints fix`. It uses the detectors
/// of the analyzer plugin and the same import handling as the quick fixes.
/// Nearest-token fixes are never applied: choosing a nearby token changes the
/// design and is left to a person.
final class BulkFixer {
  /// Creates a fixer that reads and writes through [provider].
  BulkFixer(this.provider, {ConfigLoader? loader})
    : _analyzer = ProjectAnalyzer(provider, loader: loader);

  /// The file system to read and write.
  final ResourceProvider provider;

  final ProjectAnalyzer _analyzer;

  /// Fixes the Dart files under [root].
  ///
  /// Only findings of [rules] are fixed when it is given. With [dryRun],
  /// nothing is written and the outcome lists what would change.
  Future<FixOutcome> fix(
    String root, {
    Set<RuleId>? rules,
    bool dryRun = false,
  }) async {
    final context = provider.pathContext;
    final applied = <AppliedFix>[];
    final skipped = <SkippedFix>[];
    var withoutExact = 0;
    var configured = false;
    final pending = <String, String>{};

    final walk = await _analyzer.walkFiles(
      root,
      categories: rules == null ? null : {for (final r in rules) r.category},
      onCategory: (_) => configured = true,
      onFile: (visit) async {
        final result = visit.result;
        final relative = p.posix.joinAll(
          context.split(context.relative(visit.path, from: root)),
        );
        final ignores = IgnoreComments.of(result.unit, result.content);

        ({int line, int column}) at(int offset) {
          final location = result.lineInfo.getLocation(offset);
          return (line: location.lineNumber, column: location.columnNumber);
        }

        final candidates = <(Finding, TokenSuggestion)>[];
        for (final finding in visit.findings()) {
          if (ignores.ignores(finding.rule, finding.offset)) continue;
          final exact = finding.exact;
          if (exact.isEmpty) {
            withoutExact++;
          } else if (exact.length > 1) {
            final position = at(finding.offset);
            skipped.add(
              SkippedFix(
                path: relative,
                line: position.line,
                column: position.column,
                rule: finding.rule,
                raw: finding.raw,
                reason: SkipReason.ambiguous,
                candidates: [for (final s in exact) s.reference],
              ),
            );
          } else {
            candidates.add((finding, exact.single));
          }
        }

        // Outer replacements first, so an inner one that would be replaced
        // with them is reported instead of corrupting the edit.
        candidates.sort((a, b) {
          final byLength = b.$2.length.compareTo(a.$2.length);
          return byLength != 0 ? byLength : a.$2.offset.compareTo(b.$2.offset);
        });
        final accepted = <(Finding, TokenSuggestion)>[];
        for (final candidate in candidates) {
          final (finding, suggestion) = candidate;
          final overlaps = accepted.any(
            (other) =>
                suggestion.offset < other.$2.offset + other.$2.length &&
                other.$2.offset < suggestion.offset + suggestion.length,
          );
          if (overlaps) {
            final position = at(finding.offset);
            skipped.add(
              SkippedFix(
                path: relative,
                line: position.line,
                column: position.column,
                rule: finding.rule,
                raw: finding.raw,
                reason: SkipReason.overlap,
                candidates: [suggestion.reference],
              ),
            );
          } else {
            accepted.add(candidate);
          }
        }
        if (accepted.isEmpty) return;
        accepted.sort((a, b) => a.$2.offset.compareTo(b.$2.offset));

        final builder = ChangeBuilder(session: result.session);
        final replacements = <TokenSuggestion, String>{};
        await builder.addDartFileEdit(visit.path, (edit) {
          for (final (_, suggestion) in accepted) {
            var replacement = suggestion.replacement;
            final import = suggestion.importUri;
            if (import != null) {
              final prefix = edit
                  .importLibraryElement(Uri.parse(import))
                  .prefix;
              if (prefix != null) replacement = '$prefix.$replacement';
            }
            replacements[suggestion] = replacement;
            edit.addSimpleReplacement(
              SourceRange(suggestion.offset, suggestion.length),
              replacement,
            );
          }
        });
        final edits = [
          for (final fileEdit in builder.sourceChange.edits)
            if (fileEdit.file == visit.path) ...fileEdit.edits,
        ];
        pending[visit.path] = SourceEdit.applySequence(result.content, edits);

        for (final (finding, suggestion) in accepted) {
          final position = at(finding.offset);
          applied.add(
            AppliedFix(
              path: relative,
              line: position.line,
              column: position.column,
              rule: finding.rule,
              raw: finding.raw,
              replacement: replacements[suggestion]!,
            ),
          );
        }
      },
    );

    if (walk.errors.isNotEmpty) {
      return FixOutcome(
        applied: const [],
        skipped: const [],
        withoutExactToken: 0,
        configured: configured,
        errors: walk.errors,
        warnings: walk.warnings,
      );
    }
    if (!dryRun) {
      for (final MapEntry(key: path, value: content) in pending.entries) {
        provider.getFile(path).writeAsStringSync(content);
      }
    }
    return FixOutcome(
      applied: applied
        ..sort(
          (a, b) =>
              _compare((a.path, a.line, a.column), (b.path, b.line, b.column)),
        ),
      skipped: skipped
        ..sort(
          (a, b) =>
              _compare((a.path, a.line, a.column), (b.path, b.line, b.column)),
        ),
      withoutExactToken: withoutExact,
      configured: configured,
      errors: const [],
      warnings: walk.warnings,
    );
  }

  static int _compare((String, int, int) a, (String, int, int) b) {
    final byPath = a.$1.compareTo(b.$1);
    if (byPath != 0) return byPath;
    final byLine = a.$2.compareTo(b.$2);
    return byLine != 0 ? byLine : a.$3.compareTo(b.$3);
  }
}
