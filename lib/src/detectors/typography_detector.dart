import 'package:analyzer/dart/ast/ast.dart';

import '../ast/call_view.dart';
import '../config/rule_id.dart';
import '../tokens/static_evaluator.dart';
import '../tokens/token_value.dart';
import 'detector.dart';
import 'finding.dart';

/// Detects hand-written `TextStyle(...)` constructors.
final class TypographyDetector extends Detector {
  /// Creates the detector.
  TypographyDetector(super.project);

  static const _supported = {
    'fontSize',
    'fontWeight',
    'height',
    'letterSpacing',
    'color',
  };

  final StaticEvaluator _evaluator = StaticEvaluator();

  @override
  RuleId get rule => RuleId.avoidInlineTextStyle;

  @override
  Set<NodeKind> get nodeKinds => const {
    NodeKind.instanceCreation,
    NodeKind.methodInvocation,
  };

  @override
  void check(AstNode node, FindingSink report) {
    final call = CallView.of(node);
    if (call == null || !call.matches('TextStyle')) return;
    if (isInsideTokenClass(node)) return;
    report(
      Finding(
        rule: rule,
        node: node,
        raw: 'TextStyle(...)',
        fallbackTokenClass: config.tokens[rule.category]?.className,
        suggestions: _suggestions(call),
      ),
    );
  }

  List<TokenSuggestion> _suggestions(CallView call) {
    final named = call.named;
    if (call.positional.isNotEmpty ||
        !named.keys.every(_supported.contains) ||
        !named.containsKey('fontSize') ||
        !named.containsKey('fontWeight')) {
      return const [];
    }
    final value = _evaluator.textStyle(call);
    if (value == null) return const [];
    final color = named['color'];
    if (color != null && call.node.inConstantContext) return const [];
    return [
      for (final entry in index.of(rule.category))
        if (entry.value case final TextStyleValue token when token == value)
          TokenSuggestion(
            entry: entry,
            distance: 0,
            offset: call.node.offset,
            length: call.node.length,
            replacement: color == null
                ? entry.reference
                : '${entry.reference}.copyWith(color: ${color.toSource()})',
            importUri: entry.importUri,
          ),
    ];
  }
}
