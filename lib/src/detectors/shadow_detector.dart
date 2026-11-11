import 'package:analyzer/dart/ast/ast.dart';

import '../ast/call_view.dart';
import '../config/rule_id.dart';
import '../tokens/static_evaluator.dart';
import '../tokens/token_value.dart';
import 'detector.dart';
import 'finding.dart';

/// Detects hand-written `BoxShadow` literals and lists of them.
final class ShadowDetector extends Detector {
  /// Creates the detector.
  ShadowDetector(super.project);

  final StaticEvaluator _evaluator = StaticEvaluator();

  @override
  RuleId get rule => RuleId.avoidRawShadow;

  @override
  Set<NodeKind> get nodeKinds => const {
    NodeKind.instanceCreation,
    NodeKind.methodInvocation,
    NodeKind.listLiteral,
  };

  @override
  void check(AstNode node, FindingSink report) {
    if (node is ListLiteral) {
      final hasShadow = node.elements.any(
        (e) =>
            e is Expression && (CallView.of(e)?.matches('BoxShadow') ?? false),
      );
      if (hasShadow && !isInsideTokenClass(node)) {
        report(_finding(node, _evaluator.shadow(node)));
      }
      return;
    }
    final call = CallView.of(node);
    if (call == null || !call.matches('BoxShadow')) return;
    if (node.parent is ListLiteral) return;
    if (isInsideTokenClass(node)) return;
    report(_finding(node, _evaluator.shadow(node as Expression)));
  }

  Finding _finding(AstNode node, ShadowValue? value) => Finding(
    rule: rule,
    node: node,
    raw: node is ListLiteral ? 'BoxShadow list' : 'BoxShadow(...)',
    fallbackTokenClass: config.tokens[rule.category]?.className,
    suggestions: [
      if (value != null)
        for (final entry in index.of(rule.category))
          if (entry.value == value)
            TokenSuggestion(
              entry: entry,
              distance: 0,
              offset: node.offset,
              length: node.length,
              replacement: entry.reference,
              importUri: entry.importUri,
            ),
    ],
  );
}
