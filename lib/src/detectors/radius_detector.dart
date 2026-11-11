import 'package:analyzer/dart/ast/ast.dart';

import '../ast/call_view.dart';
import '../config/rule_id.dart';
import '../tokens/nearest_token_matcher.dart';
import '../tokens/token_index.dart';
import '../tokens/token_value.dart';
import 'detector.dart';
import 'finding.dart';
import 'number_suggestions.dart';

/// Detects numeric literals used as corner radii.
final class RadiusDetector extends Detector {
  /// Creates the detector.
  RadiusDetector(super.project);

  @override
  RuleId get rule => RuleId.avoidRawRadius;

  @override
  Set<NodeKind> get nodeKinds => const {
    NodeKind.instanceCreation,
    NodeKind.methodInvocation,
  };

  @override
  void check(AstNode node, FindingSink report) {
    final call = CallView.of(node);
    if (call == null) return;
    if (call.matches('BorderRadius', 'circular')) {
      final literal = _single(call);
      if (literal != null) {
        _report(report, call.node, literal, wholeAs: _Whole.borderRadius);
      }
    } else if (call.matches('BorderRadius', 'all')) {
      final inner = _single(call, allowCall: true);
      final innerCall = CallView.of(inner);
      if (innerCall != null && innerCall.matches('Radius', 'circular')) {
        final literal = _single(innerCall);
        if (literal != null) {
          _report(
            report,
            call.node,
            literal,
            wholeAs: _Whole.borderRadius,
            innerRadius: innerCall.node,
          );
        }
      }
    } else if (call.matches('Radius', 'circular')) {
      if (_isArgumentOfBorderRadiusAll(call.node)) return;
      final literal = _single(call);
      if (literal != null) {
        _report(report, call.node, literal, wholeAs: _Whole.radius);
      }
    }
  }

  AstNode? _single(CallView call, {bool allowCall = false}) {
    final args = call.positional;
    if (args.length != 1) return null;
    final argument = args.single;
    if (allowCall) return argument;
    return literalValue(argument) == null ? null : argument;
  }

  bool _isArgumentOfBorderRadiusAll(AstNode node) {
    final list = node.parent;
    if (list is! ArgumentList) return false;
    final owner = CallView.of(list.parent);
    return owner != null && owner.matches('BorderRadius', 'all');
  }

  void _report(
    FindingSink report,
    AstNode reportNode,
    AstNode literal, {
    required _Whole wholeAs,
    AstNode? innerRadius,
  }) {
    final value = literalValue(literal);
    if (value == null || value == 0) return;
    if (config.allowRadius.contains(value)) return;
    if (isInsideTokenClass(reportNode)) return;

    final entries = index.of(rule.category);
    final suggestions = <TokenSuggestion>[];

    TokenSuggestion suggestion(TokenMatch<TokenEntry> match, AstNode target) =>
        TokenSuggestion(
          entry: match.item,
          distance: match.distance,
          offset: target.offset,
          length: target.length,
          replacement: match.item.reference,
          importUri: match.item.importUri,
        );

    List<TokenMatch<TokenEntry>> matchKind(
      bool Function(TokenValue) isKind,
      double Function(TokenValue) valueOf,
    ) => NearestTokenMatcher.matchNumber<TokenEntry>(
      value,
      [
        for (final entry in entries)
          if (isKind(entry.value)) entry,
      ],
      (entry) => valueOf(entry.value),
      tolerance: config.radiusTolerance,
    );

    final borderRadius = matchKind(
      (v) => v is BorderRadiusValue,
      (v) => (v as BorderRadiusValue).value,
    );
    final radius = matchKind(
      (v) => v is RadiusValue,
      (v) => (v as RadiusValue).value,
    );
    if (wholeAs == _Whole.borderRadius) {
      suggestions.addAll(borderRadius.map((m) => suggestion(m, reportNode)));
      if (innerRadius != null) {
        suggestions.addAll(radius.map((m) => suggestion(m, innerRadius)));
      }
    } else {
      suggestions.addAll(radius.map((m) => suggestion(m, reportNode)));
    }
    suggestions.addAll(
      numberSuggestions(
        entries: entries,
        literal: literal,
        value: value,
        tolerance: config.radiusTolerance,
      ),
    );
    suggestions.sort((a, b) => a.distance.compareTo(b.distance));

    report(
      Finding(
        rule: rule,
        node: reportNode,
        raw: reportNode.toSource(),
        fallbackTokenClass: config.tokens[rule.category]?.className,
        suggestions: suggestions,
      ),
    );
  }
}

enum _Whole { borderRadius, radius }
