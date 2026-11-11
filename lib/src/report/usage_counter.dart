import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import '../config/config_loader.dart';
import '../config/rule_id.dart';

/// Counts references to design-system tokens and components in a resolved
/// syntax tree.
final class UsageCounter extends RecursiveAstVisitor<void> {
  /// Creates a counter for [project] that counts only [categories].
  UsageCounter(this.project, this.categories) {
    for (final category in categories) {
      if (category == DesignCategory.component) continue;
      final entries = project.index.of(category);
      for (final entry in entries) {
        _classCategories[entry.className] = category;
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

  final Map<String, DesignCategory> _classCategories = {};
  final Set<String> _componentClasses = {};

  void _count(DesignCategory category) {
    if (categories.contains(category)) {
      counts[category] = (counts[category] ?? 0) + 1;
    }
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
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
