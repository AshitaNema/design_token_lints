import 'package:analyzer/dart/ast/ast.dart';

import '../ast/call_view.dart';
import '../config/rule_id.dart';
import '../tokens/nearest_token_matcher.dart';
import '../tokens/static_evaluator.dart';
import '../tokens/token_index.dart';
import '../tokens/token_value.dart';
import 'detector.dart';
import 'element_checks.dart';
import 'finding.dart';

/// Detects raw colors: `Color(...)` constructors and `Colors.*` members.
final class ColorDetector extends Detector {
  /// Creates the detector.
  ColorDetector(super.project);

  static const _constructors = {null, 'fromARGB', 'fromRGBO', 'from'};

  final StaticEvaluator _evaluator = StaticEvaluator();

  @override
  RuleId get rule => RuleId.avoidRawColor;

  @override
  Set<NodeKind> get nodeKinds => const {
    NodeKind.instanceCreation,
    NodeKind.methodInvocation,
    NodeKind.prefixedIdentifier,
    NodeKind.propertyAccess,
    NodeKind.indexExpression,
  };

  @override
  void check(AstNode node, FindingSink report) {
    if (node is InstanceCreationExpression || node is MethodInvocation) {
      _checkConstructor(node, report);
    } else if (node is PrefixedIdentifier ||
        node is PropertyAccess ||
        node is IndexExpression) {
      _checkPalette(node as Expression, report);
    }
  }

  void _checkConstructor(AstNode node, FindingSink report) {
    final call = CallView.of(node);
    if (call == null ||
        call.typeName != 'Color' ||
        !_constructors.contains(call.constructorName)) {
      return;
    }
    final argb = _evaluator.colorArgb(call.node);
    if (argb == null || config.isColorAllowed(colorValue: argb)) return;
    if (isInsideTokenClass(node)) return;
    report(_finding(node, argb));
  }

  void _checkPalette(Expression node, FindingSink report) {
    final ref = materialColorOf(node);
    if (ref == null) return;
    final parent = node.parent;
    if (parent is Expression && materialColorOf(parent) != null) return;
    if (!_isFlutterColors(node)) return;
    if (config.isColorAllowed(colorName: ref.name) ||
        config.isColorAllowed(colorValue: ref.argb)) {
      return;
    }
    if (isInsideTokenClass(node)) return;
    report(_finding(node, ref.argb));
  }

  bool _isFlutterColors(Expression node) {
    final prefix = switch (node) {
      PrefixedIdentifier() => node.prefix,
      PropertyAccess(target: final PrefixedIdentifier target) => target.prefix,
      IndexExpression(target: final PrefixedIdentifier target) => target.prefix,
      _ => null,
    };
    return isDeclaredInFlutter(prefix?.element);
  }

  Finding _finding(AstNode node, int argb) {
    final entries = index.of(DesignCategory.color);
    final matches = NearestTokenMatcher.matchColor<TokenEntry>(
      argb,
      [
        for (final entry in entries)
          if (entry.value is ColorValue) entry,
      ],
      (entry) => (entry.value as ColorValue).argb,
      maxDeltaE: config.colorDeltaE,
    );
    return Finding(
      rule: rule,
      node: node,
      raw: node.toSource(),
      fallbackTokenClass: config.tokens[DesignCategory.color]?.className,
      suggestions: [
        for (final match in matches)
          TokenSuggestion(
            entry: match.item,
            distance: match.distance,
            offset: node.offset,
            length: node.length,
            replacement: match.item.reference,
            importUri: match.item.importUri,
          ),
      ],
    );
  }
}
