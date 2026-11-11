import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';

import '../config/config_loader.dart';
import '../config/rule_id.dart';
import '../detectors/detectors.dart';
import '../detectors/finding.dart';

/// How many exact and nearest replacements are offered per diagnostic.
const int maxExactFixes = 2;

/// How many nearest replacements are offered per diagnostic.
const int maxNearestFixes = 3;

/// Replaces a flagged expression with a suggested token.
///
/// One producer offers one replacement: the [rank]-th exact suggestion, or the
/// [rank]-th nearest suggestion when [nearest] is set. The plugin registers a
/// producer for each rank so that ties and several near matches are all
/// offered.
final class TokenFix extends ResolvedCorrectionProducer {
  /// Creates the producer.
  TokenFix({
    required super.context,
    required this.rule,
    required this.nearest,
    required this.rank,
    ConfigLoader? loader,
  }) : _loader = loader ?? ConfigLoader.shared;

  /// The rule whose diagnostics are fixed.
  final RuleId rule;

  /// Whether this producer offers a nearest (non-exact) replacement.
  final bool nearest;

  /// The position within the exact or nearest suggestions.
  final int rank;

  final ConfigLoader _loader;

  List<String>? _arguments;

  /// The kind of fix offered by the producer for [rule].
  static FixKind kindFor(RuleId rule, {required bool nearest, int rank = 0}) {
    final suffix = nearest ? '.nearest' : '';
    final position = rank == 0 ? '' : '.${rank + 1}';
    return FixKind(
      'design_token_lints.fix.${rule.code}$suffix$position',
      nearest ? DartFixKindPriority.inFile : DartFixKindPriority.standard,
      _message(rule, nearest: nearest),
    );
  }

  static String _message(RuleId rule, {required bool nearest}) {
    final withRaw =
        rule == RuleId.avoidMagicSpacing ||
        rule == RuleId.avoidRawRadius ||
        rule == RuleId.preferDesignSystemComponent;
    if (nearest) {
      return withRaw
          ? 'Replace {0} with nearest token {1}'
          : 'Replace with nearest token {1}';
    }
    return withRaw ? 'Replace {0} with {1}' : 'Replace with {1}';
  }

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => kindFor(rule, nearest: nearest, rank: rank);

  @override
  List<String>? get fixArguments => _arguments;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final finding = _findFinding();
    if (finding == null) return;
    final candidates = nearest ? finding.nearest : finding.exact;
    if (rank >= candidates.length) return;
    final suggestion = candidates[rank];
    final detail = nearest
        ? '${suggestion.replacement} (${_distance(suggestion.distance)})'
        : suggestion.replacement;
    _arguments = [finding.raw, detail];

    await builder.addDartFileEdit(file, (edit) {
      var replacement = suggestion.replacement;
      final import = suggestion.importUri;
      if (import != null) {
        final prefix = edit.importLibraryElement(Uri.parse(import)).prefix;
        if (prefix != null) replacement = '$prefix.$replacement';
      }
      edit.addSimpleReplacement(
        SourceRange(suggestion.offset, suggestion.length),
        replacement,
      );
    });
  }

  String _distance(double distance) {
    final text = distance.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
    return rule == RuleId.avoidRawColor ? 'ΔE $text' : 'Δ$text';
  }

  Finding? _findFinding() {
    final offset = diagnosticOffset;
    final length = diagnosticLength;
    if (offset == null || length == null) return null;
    final lookup = _loader.lookup(unitResult.file);
    if (!lookup.project.isRuleActive(rule)) return null;
    final detector = Detectors.forRule(rule, lookup.project);
    final matches = <Finding>[];
    var current = coveringNode;
    while (current != null && matches.isEmpty) {
      detector.check(current, (finding) {
        if (finding.offset == offset && finding.length == length) {
          matches.add(finding);
        }
      });
      current = current.parent;
    }
    return matches.isEmpty ? null : matches.first;
  }
}
