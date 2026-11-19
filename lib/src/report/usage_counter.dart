import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../config/config_loader.dart';
import '../config/rule_id.dart';
import '../detectors/element_checks.dart';

/// Counts references to design-system tokens and components in a resolved
/// syntax tree.
///
/// Colors read from Flutter's `ColorScheme` and text styles read from its
/// `TextTheme` (`Theme.of(context).colorScheme.primary`,
/// `TextTheme.of(context).bodyMedium`) count as color and typography uses:
/// they come from the app's theme rather than being written by hand.
final class UsageCounter extends RecursiveAstVisitor<void> {
  /// Creates a counter for [project] that counts only [categories].
  UsageCounter(this.project, this.categories) {
    for (final category in categories) {
      if (category == DesignCategory.component) continue;
      final entries = project.index.of(category);
      for (final entry in entries) {
        if (entry.isInstanceField) {
          (_instanceMembers[entry.className] ??= {})[entry.name] = category;
        } else {
          _classCategories[entry.className] = category;
        }
      }
    }
    for (final replacement in project.config.components.values) {
      _componentClasses.add(replacement.replacement);
    }
  }

  /// The project whose tokens are counted.
  final ProjectConfig project;

  /// The categories to count.
  final Set<DesignCategory> categories;

  /// The number of usages per category.
  final Map<DesignCategory, int> counts = {};

  /// Theme classes whose members count as uses, with the category and the
  /// type a member must have to count.
  static const _themeClasses = {
    'ColorScheme': (DesignCategory.color, 'Color'),
    'TextTheme': (DesignCategory.typography, 'TextStyle'),
  };

  final Map<String, DesignCategory> _classCategories = {};

  /// For `ThemeExtension`-style classes, field name to category by class.
  final Map<String, Map<String, DesignCategory>> _instanceMembers = {};
  final Set<String> _componentClasses = {};

  void _count(DesignCategory category) {
    if (categories.contains(category)) {
      counts[category] = (counts[category] ?? 0) + 1;
    }
  }

  /// Counts [access] when it reads a color or text style from a theme object
  /// [target].
  void _countThemeMember(Expression? target, Expression access) {
    final type = target?.staticType;
    if (type is! InterfaceType) return;
    final theme = _themeClasses[type.element.name];
    if (theme == null || !isDeclaredInFlutter(type.element)) return;
    final value = access.staticType;
    if (value is InterfaceType && value.element.name == theme.$2) {
      _count(theme.$1);
    }
  }

  /// Counts a read of the token field [member] from an instance of a
  /// configured `ThemeExtension`-style class.
  void _countInstanceMember(Expression? target, String member) {
    if (_instanceMembers.isEmpty) return;
    final type = target?.staticType;
    if (type is! InterfaceType) return;
    final category = _instanceMembers[type.element.name]?[member];
    if (category != null) _count(category);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    _countThemeMember(node.realTarget, node);
    _countInstanceMember(node.realTarget, node.propertyName.name);
    super.visitPropertyAccess(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    _countThemeMember(node.prefix, node);
    _countInstanceMember(node.prefix, node.identifier.name);
    final prefix = node.prefix.element;
    if (prefix is InterfaceElement) {
      final category = _classCategories[prefix.name];
      if (category != null) _count(category);
    } else if (prefix is PrefixElement && node.parent is PropertyAccess) {
      // `ds.AppColors.primary`: the class is the identifier, the member is
      // the property of the enclosing access.
      final element = node.identifier.element;
      if (element is InterfaceElement) {
        final category = _classCategories[element.name];
        if (category != null) _count(category);
      }
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (_componentClasses.isNotEmpty) {
      final element = node.constructorName.type.element;
      if (element is ClassElement && _componentClasses.contains(element.name)) {
        _count(DesignCategory.component);
      }
    }
    super.visitInstanceCreationExpression(node);
  }
}
