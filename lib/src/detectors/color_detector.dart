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
    final translucent = matches.any((match) => match.distance == 0)
        ? const <TokenSuggestion>[]
        : _translucentSuggestions(node, argb, entries);
    return Finding(
      rule: rule,
      node: node,
      raw: node.toSource(),
      fallbackTokenClass: config.tokens[DesignCategory.color]?.className,
      suggestions: [
        ...translucent,
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

  /// Suggests `Token.withValues(alpha: …)` for a translucent color whose red,
  /// green and blue channels equal an opaque token.
  ///
  /// The result is identical at 8 bits per channel. No suggestion is made
  /// where a method call is not allowed: in a constant context or in a
  /// parameter's default value.
  List<TokenSuggestion> _translucentSuggestions(
    AstNode node,
    int argb,
    List<TokenEntry> entries,
  ) {
    final alpha = (argb >> 24) & 0xFF;
    if (alpha == 0xFF) return const [];
    if (node is! Expression || node.inConstantContext) return const [];
    if (node.thisOrAncestorOfType<FormalParameterDefaultClause>() != null) {
      return const [];
    }
    final rgb = argb & 0xFFFFFF;
    final text = alphaLiteral(alpha);
    return [
      for (final entry in entries)
        if (entry.value case ColorValue(
          argb: final tokenArgb,
        ) when (tokenArgb >> 24) & 0xFF == 0xFF && tokenArgb & 0xFFFFFF == rgb)
          TokenSuggestion(
            entry: entry,
            distance: 0,
            offset: node.offset,
            length: node.length,
            replacement: '${entry.reference}.withValues(alpha: $text)',
            importUri: entry.importUri,
            label: '${entry.reference}.withValues(alpha: $text)',
          ),
    ];
  }
}

/// The shortest decimal literal for the 8-bit [alpha] that converts back to
/// the same value, the way Flutter does (`(a * 255).round()`).
///
/// Two decimals are used when they round-trip, otherwise three, which always
/// do: `0x80` is `0.5`, `0x7F` is `0.498`.
String alphaLiteral(int alpha) {
  for (final digits in const [2, 3]) {
    final text = (alpha / 255).toStringAsFixed(digits);
    if ((double.parse(text) * 255).round() == alpha) {
      return text
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }
  }
  throw StateError('unreachable: three decimals always round-trip');
}
