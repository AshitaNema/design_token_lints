import 'package:analyzer/dart/ast/ast.dart';

import '../ast/call_view.dart';
import '../config/rule_id.dart';
import 'detector.dart';
import 'finding.dart';
import 'number_suggestions.dart';

/// Detects numeric literals used as spacing.
final class SpacingDetector extends Detector {
  /// Creates the detector.
  SpacingDetector(super.project);

  /// Constructors whose arguments are spacing, keyed by `Type.constructor`,
  /// with the names of the arguments that carry spacing. Numbers stand for
  /// positional arguments.
  static const Map<String, List<Object>> _spacingArguments = {
    'EdgeInsets.all': [0],
    'EdgeInsets.symmetric': ['horizontal', 'vertical'],
    'EdgeInsets.only': ['left', 'top', 'right', 'bottom'],
    'EdgeInsets.fromLTRB': [0, 1, 2, 3],
    'EdgeInsetsDirectional.all': [0],
    'EdgeInsetsDirectional.symmetric': ['horizontal', 'vertical'],
    'EdgeInsetsDirectional.only': ['start', 'top', 'end', 'bottom'],
    'EdgeInsetsDirectional.fromSTEB': [0, 1, 2, 3],
    'SizedBox': ['width', 'height'],
    'SizedBox.square': ['dimension'],
    'Gap': [0],
    'SliverGap': [0],
  };

  @override
  RuleId get rule => RuleId.avoidMagicSpacing;

  @override
  Set<NodeKind> get nodeKinds => const {
    NodeKind.instanceCreation,
    NodeKind.methodInvocation,
  };

  @override
  void check(AstNode node, FindingSink report) {
    final call = CallView.of(node);
    if (call == null) return;
    final key = call.constructorName == null
        ? call.typeName
        : '${call.typeName}.${call.constructorName}';
    final arguments = _spacingArguments[key];
    if (arguments == null) return;
    final positional = call.positional;
    final named = call.named;
    for (final argument in arguments) {
      final expression = argument is int
          ? (argument < positional.length ? positional[argument] : null)
          : named[argument];
      if (expression == null) continue;
      final value = literalValue(expression);
      if (value == null || value == 0) continue;
      if (config.allowSpacing.contains(value)) continue;
      if (isInsideTokenClass(expression)) continue;
      report(
        Finding(
          rule: rule,
          node: expression,
          raw: expression.toSource(),
          fallbackTokenClass: config.tokens[rule.category]?.className,
          suggestions: numberSuggestions(
            entries: index.of(rule.category),
            literal: expression,
            value: value,
            tolerance: config.spacingTolerance,
          ),
        ),
      );
    }
  }
}
