import 'package:analyzer/dart/ast/ast.dart';

import '../ast/call_view.dart';
import '../config/rule_id.dart';
import 'detector.dart';
import 'finding.dart';
import 'number_suggestions.dart';

/// Detects numeric literals passed to known constructor arguments, such as
/// `Icon(size: 22)` or `Card(elevation: 2)`.
///
/// `0`, negative numbers, allow-listed values and non-literal expressions are
/// ignored. The literal is reported and replaced, so the call stays in place.
final class NumericArgumentDetector extends Detector {
  /// The detector of `avoid_raw_icon_size`.
  NumericArgumentDetector.iconSize(super.project)
    : rule = RuleId.avoidRawIconSize,
      _arguments = _iconSizeArguments,
      _allowed = (() => project.config.allowIconSize),
      _tolerance = (() => project.config.iconSizeTolerance);

  /// The detector of `avoid_raw_elevation`.
  NumericArgumentDetector.elevation(super.project)
    : rule = RuleId.avoidRawElevation,
      _arguments = _elevationArguments,
      _allowed = (() => project.config.allowElevation),
      _tolerance = (() => project.config.elevationTolerance);

  /// Calls whose arguments are icon sizes, keyed by `Type` or
  /// `Type.constructor`, with the names of the named arguments.
  static const Map<String, List<String>> _iconSizeArguments = {
    'Icon': ['size'],
    'ImageIcon': ['size'],
    'IconButton': ['iconSize'],
    'IconButton.filled': ['iconSize'],
    'IconButton.filledTonal': ['iconSize'],
    'IconButton.outlined': ['iconSize'],
    'IconThemeData': ['size'],
  };

  /// Calls whose arguments are elevations.
  static const Map<String, List<String>> _elevationArguments = {
    'Material': ['elevation'],
    'Card': ['elevation'],
    'Card.filled': ['elevation'],
    'Card.outlined': ['elevation'],
    'AppBar': ['elevation', 'scrolledUnderElevation'],
    'SliverAppBar': ['elevation', 'scrolledUnderElevation'],
    'BottomAppBar': ['elevation'],
    'NavigationBar': ['elevation'],
    'Drawer': ['elevation'],
    'Dialog': ['elevation'],
    'AlertDialog': ['elevation'],
    'BottomSheet': ['elevation'],
    'PopupMenuButton': ['elevation'],
    'Chip': ['elevation'],
    'FloatingActionButton': ['elevation'],
    'FloatingActionButton.small': ['elevation'],
    'FloatingActionButton.large': ['elevation'],
    'FloatingActionButton.extended': ['elevation'],
    'PhysicalModel': ['elevation'],
    'PhysicalShape': ['elevation'],
    'ElevatedButton.styleFrom': ['elevation'],
    'FilledButton.styleFrom': ['elevation'],
    'OutlinedButton.styleFrom': ['elevation'],
    'TextButton.styleFrom': ['elevation'],
  };

  @override
  final RuleId rule;

  final Map<String, List<String>> _arguments;
  final Set<double> Function() _allowed;
  final double Function() _tolerance;

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
    final arguments = _arguments[key];
    if (arguments == null) return;
    final named = call.named;
    for (final argument in arguments) {
      final expression = named[argument];
      if (expression == null) continue;
      final value = literalValue(expression);
      if (value == null || value == 0) continue;
      if (_allowed().contains(value)) continue;
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
            tolerance: _tolerance(),
          ),
        ),
      );
    }
  }
}
