import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/error/error.dart';

import 'config/rule_id.dart';
import 'fixes/token_fix.dart';
import 'rules/design_token_rule.dart';

/// The `design_token_lints` analyzer plugin.
///
/// Every rule is registered as a warning rule so that it is on by default; a
/// rule reports nothing until the project configures the matching tokens.
final class DesignTokenLintsPlugin extends Plugin {
  @override
  String get name => 'design_token_lints';

  @override
  void register(PluginRegistry registry) {
    for (final id in RuleId.values) {
      registry.registerWarningRule(DesignTokenRule(id));
    }
    registerFixes(registry.registerFixForRule);
  }
}

/// Creates a correction producer for a diagnostic.
typedef FixGenerator =
    CorrectionProducer<ParsedUnitResult> Function({
      required CorrectionProducerContext context,
    });

/// Registers every quick fix through [register].
///
/// [register] receives the diagnostic code and a producer generator. Exposed
/// separately from the plugin so tests can register fixes without registering
/// the rules a second time.
void registerFixes(
  void Function(DiagnosticCode code, FixGenerator generator) register,
) {
  for (final id in RuleId.values) {
    final code = DtlCodes.of(id);
    for (var rank = 0; rank < maxExactFixes; rank++) {
      register(
        code,
        ({required context}) =>
            TokenFix(context: context, rule: id, nearest: false, rank: rank),
      );
    }
    if (!id.offersNearestFixes) continue;
    for (var rank = 0; rank < maxNearestFixes; rank++) {
      register(
        code,
        ({required context}) =>
            TokenFix(context: context, rule: id, nearest: true, rank: rank),
      );
    }
  }
}
