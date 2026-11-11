import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';

import '../ast/call_view.dart';
import '../config/rule_id.dart';
import 'material_colors.dart';
import 'token_value.dart';

/// Resolves a reference such as `base` or `AppSpacing.base` to the expression
/// it was declared with.
typedef ReferenceResolver = Expression? Function(String? prefix, String name);

/// A member of Flutter's `Colors` palette that an expression refers to.
typedef MaterialColorRef = ({String name, int argb});

/// Returns the palette color that [expression] spells (`Colors.red`,
/// `Colors.red.shade100`, `Colors.red[100]`), or `null`.
///
/// This is a syntactic check; callers that need to be sure `Colors` is
/// Flutter's class verify the resolved element themselves.
MaterialColorRef? materialColorOf(Expression expression) {
  String? name;
  if (expression is PrefixedIdentifier && expression.prefix.name == 'Colors') {
    name = expression.identifier.name;
  } else if (expression is PropertyAccess) {
    final target = expression.target;
    final property = expression.propertyName.name;
    if (target is PrefixedIdentifier &&
        target.prefix.name == 'Colors' &&
        property.startsWith('shade')) {
      name = '${target.identifier.name}.${property.substring(5)}';
    }
  } else if (expression is IndexExpression) {
    final target = expression.target;
    final index = expression.index;
    if (target is PrefixedIdentifier &&
        target.prefix.name == 'Colors' &&
        index is IntegerLiteral) {
      name = '${target.identifier.name}.${index.value}';
    }
  }
  if (name == null) return null;
  final argb = materialColorValues[name];
  return argb == null ? null : (name: name, argb: argb);
}

/// Evaluates the constant expressions that appear in design-token
/// declarations and in raw values, without resolving the code.
///
/// Anything it cannot evaluate yields `null`.
final class StaticEvaluator {
  /// Creates an evaluator. [resolve] looks up references to other constants.
  StaticEvaluator({ReferenceResolver? resolve}) : _resolve = resolve;

  final ReferenceResolver? _resolve;
  final Set<String> _active = {};

  /// Evaluates [expression] as the value of a token of [category].
  TokenValue? evaluate(DesignCategory category, Expression expression) {
    switch (category) {
      case DesignCategory.color:
        final argb = colorArgb(expression);
        return argb == null ? null : ColorValue(argb);
      case DesignCategory.spacing:
        final value = number(expression);
        return value == null ? null : NumberValue(value.toDouble());
      case DesignCategory.radius:
        final value = number(expression);
        if (value != null) return NumberValue(value.toDouble());
        return radius(expression);
      case DesignCategory.typography:
        return _textStyleOf(expression);
      case DesignCategory.shadow:
        return shadow(expression);
      case DesignCategory.component:
        return null;
    }
  }

  /// Evaluates a numeric expression.
  num? number(Expression expression) {
    final node = _unwrap(expression);
    switch (node) {
      case IntegerLiteral():
        return node.value;
      case DoubleLiteral():
        return node.value;
      case PrefixExpression():
        final operand = number(node.operand);
        if (operand == null) return null;
        return switch (node.operator.type) {
          TokenType.MINUS => -operand,
          TokenType.PLUS => operand,
          _ => null,
        };
      case BinaryExpression():
        final left = number(node.leftOperand);
        final right = number(node.rightOperand);
        if (left == null || right == null) return null;
        return switch (node.operator.type) {
          TokenType.PLUS => left + right,
          TokenType.MINUS => left - right,
          TokenType.STAR => left * right,
          TokenType.SLASH => right == 0 ? null : left / right,
          TokenType.TILDE_SLASH => right == 0 ? null : left ~/ right,
          TokenType.PERCENT => right == 0 ? null : left % right,
          _ => null,
        };
      case SimpleIdentifier():
        return _follow(null, node.name, number);
      case PrefixedIdentifier():
        return _follow(node.prefix.name, node.identifier.name, number);
      default:
        return null;
    }
  }

  /// Evaluates a color expression to `0xAARRGGBB`.
  int? colorArgb(Expression expression) {
    final node = _unwrap(expression);
    final call = CallView.of(node);
    if (call != null && call.typeName == 'Color') {
      return _colorFromCall(call);
    }
    final material = materialColorOf(node);
    if (material != null) return material.argb;
    return switch (node) {
      SimpleIdentifier() => _follow(null, node.name, colorArgb),
      PrefixedIdentifier() => _follow(
        node.prefix.name,
        node.identifier.name,
        colorArgb,
      ),
      _ => null,
    };
  }

  /// Evaluates a `FontWeight` expression to its numeric weight.
  int? fontWeight(Expression expression) {
    final node = _unwrap(expression);
    if (node is PrefixedIdentifier && node.prefix.name == 'FontWeight') {
      final name = node.identifier.name;
      if (name == 'normal') return 400;
      if (name == 'bold') return 700;
      final match = RegExp(r'^w([1-9]00)$').firstMatch(name);
      if (match != null) return int.parse(match.group(1)!);
      return null;
    }
    return switch (node) {
      SimpleIdentifier() => _follow(null, node.name, fontWeight),
      PrefixedIdentifier() => _follow(
        node.prefix.name,
        node.identifier.name,
        fontWeight,
      ),
      _ => null,
    };
  }

  /// Evaluates `Radius.circular(n)`, `BorderRadius.circular(n)` and
  /// `BorderRadius.all(Radius.circular(n))`.
  TokenValue? radius(Expression expression) {
    final node = _unwrap(expression);
    final call = CallView.of(node);
    if (call != null) {
      if (call.matches('Radius', 'circular')) {
        final value = _singleNumber(call);
        return value == null ? null : RadiusValue(value);
      }
      if (call.matches('BorderRadius', 'circular')) {
        final value = _singleNumber(call);
        return value == null ? null : BorderRadiusValue(value);
      }
      if (call.matches('BorderRadius', 'all')) {
        final args = call.positional;
        if (args.length != 1) return null;
        final inner = radius(args.single);
        return inner is RadiusValue ? BorderRadiusValue(inner.value) : null;
      }
      return null;
    }
    return switch (node) {
      SimpleIdentifier() => _follow(null, node.name, radius),
      PrefixedIdentifier() => _follow(
        node.prefix.name,
        node.identifier.name,
        radius,
      ),
      _ => null,
    };
  }

  /// Evaluates a `TextStyle(...)` call.
  ///
  /// Returns `null` if any of the identifying properties is present but
  /// cannot be evaluated.
  TextStyleValue? textStyle(CallView call) {
    if (!call.matches('TextStyle')) return null;
    final named = call.named;
    double? fontSize;
    double? height;
    double? letterSpacing;
    int? weight;
    if (named['fontSize'] case final e?) {
      fontSize = number(e)?.toDouble();
      if (fontSize == null) return null;
    }
    if (named['height'] case final e?) {
      height = number(e)?.toDouble();
      if (height == null) return null;
    }
    if (named['letterSpacing'] case final e?) {
      letterSpacing = number(e)?.toDouble();
      if (letterSpacing == null) return null;
    }
    if (named['fontWeight'] case final e?) {
      weight = fontWeight(e);
      if (weight == null) return null;
    }
    return TextStyleValue(
      fontSize: fontSize,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  TextStyleValue? _textStyleOf(Expression expression) {
    final node = _unwrap(expression);
    final call = CallView.of(node);
    if (call != null) return textStyle(call);
    return switch (node) {
      SimpleIdentifier() => _follow(null, node.name, _textStyleOf),
      PrefixedIdentifier() => _follow(
        node.prefix.name,
        node.identifier.name,
        _textStyleOf,
      ),
      _ => null,
    };
  }

  /// Evaluates a `BoxShadow(...)` call.
  ShadowLayer? shadowLayer(CallView call) {
    if (!call.matches('BoxShadow')) return null;
    final named = call.named;
    final color = named['color'] == null
        ? 0xFF000000
        : colorArgb(named['color']!);
    final blur = named['blurRadius'] == null ? 0 : number(named['blurRadius']!);
    final spread = named['spreadRadius'] == null
        ? 0
        : number(named['spreadRadius']!);
    if (color == null || blur == null || spread == null) return null;
    var dx = 0.0;
    var dy = 0.0;
    final offset = named['offset'];
    if (offset != null) {
      final offsetCall = CallView.of(_unwrap(offset));
      if (offsetCall == null || !offsetCall.matches('Offset')) return null;
      final args = offsetCall.positional;
      if (args.length != 2) return null;
      final x = number(args[0]);
      final y = number(args[1]);
      if (x == null || y == null) return null;
      dx = x.toDouble();
      dy = y.toDouble();
    }
    return ShadowLayer(
      color: color,
      blurRadius: blur.toDouble(),
      spreadRadius: spread.toDouble(),
      dx: dx,
      dy: dy,
    );
  }

  /// Evaluates a `BoxShadow(...)` or a list literal of them.
  ShadowValue? shadow(Expression expression) {
    final node = _unwrap(expression);
    if (node is ListLiteral) {
      final layers = <ShadowLayer>[];
      for (final element in node.elements) {
        final call = element is Expression
            ? CallView.of(_unwrap(element))
            : null;
        final layer = call == null ? null : shadowLayer(call);
        if (layer == null) return null;
        layers.add(layer);
      }
      return ShadowValue(layers, isList: true);
    }
    final call = CallView.of(node);
    if (call != null) {
      final layer = shadowLayer(call);
      return layer == null ? null : ShadowValue([layer], isList: false);
    }
    return switch (node) {
      SimpleIdentifier() => _follow(null, node.name, shadow),
      PrefixedIdentifier() => _follow(
        node.prefix.name,
        node.identifier.name,
        shadow,
      ),
      _ => null,
    };
  }

  double? _singleNumber(CallView call) {
    final args = call.positional;
    if (args.length != 1) return null;
    return number(args.single)?.toDouble();
  }

  int? _colorFromCall(CallView call) {
    int channel(num value) => value.round().clamp(0, 255);
    int pack(int a, int r, int g, int b) =>
        (a << 24) | (r << 16) | (g << 8) | b;
    final args = call.positional;
    switch (call.constructorName) {
      case null:
        if (args.length != 1) return null;
        final value = number(args.single);
        return value is int ? value & 0xFFFFFFFF : null;
      case 'fromARGB':
        if (args.length != 4) return null;
        final v = [for (final a in args) number(a)];
        if (v.any((e) => e == null)) return null;
        return pack(
          channel(v[0]!),
          channel(v[1]!),
          channel(v[2]!),
          channel(v[3]!),
        );
      case 'fromRGBO':
        if (args.length != 4) return null;
        final v = [for (final a in args) number(a)];
        if (v.any((e) => e == null)) return null;
        return pack(
          channel(v[3]! * 255),
          channel(v[0]!),
          channel(v[1]!),
          channel(v[2]!),
        );
      case 'from':
        final named = call.named;
        final v = [
          for (final key in const ['alpha', 'red', 'green', 'blue'])
            named[key] == null ? null : number(named[key]!),
        ];
        if (v.any((e) => e == null)) return null;
        return pack(
          channel(v[0]! * 255),
          channel(v[1]! * 255),
          channel(v[2]! * 255),
          channel(v[3]! * 255),
        );
    }
    return null;
  }

  T? _follow<T>(String? prefix, String name, T? Function(Expression) eval) {
    final resolver = _resolve;
    if (resolver == null) return null;
    final key = '${prefix ?? ''}.$name';
    if (!_active.add(key)) return null;
    try {
      final target = resolver(prefix, name);
      return target == null ? null : eval(target);
    } finally {
      _active.remove(key);
    }
  }

  static Expression _unwrap(Expression expression) {
    var node = expression;
    while (node is ParenthesizedExpression) {
      node = node.expression;
    }
    return node;
  }
}
