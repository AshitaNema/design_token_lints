import 'package:analyzer/dart/ast/ast.dart';

import 'finding.dart';

/// Whether [node] may be replaced by an expression that is not constant,
/// such as a method call or an instance field.
///
/// It may not in a constant context (`const` variables, collections and
/// constructor calls) or in a parameter's default value.
bool allowsNonConstant(AstNode node) {
  if (node is! Expression || node.inConstantContext) return false;
  return node.thisOrAncestorOfType<FormalParameterDefaultClause>() == null;
}

/// Whether a `BuildContext` named `context` is in scope at [node].
///
/// It is when an enclosing function, method or closure has a parameter
/// `context` declared as `BuildContext` (or untyped, as in builder callbacks
/// like `(context) => …`), or when [node] is in an instance member of a
/// class that extends `State`, which has a `context` getter.
bool hasBuildContext(AstNode node) {
  for (AstNode? current = node; current != null; current = current.parent) {
    final parameters = switch (current) {
      FunctionExpression() => current.parameters,
      MethodDeclaration() => current.parameters,
      ConstructorDeclaration() => current.parameters,
      _ => null,
    };
    if (parameters != null) {
      for (final parameter in parameters.parameters) {
        if (parameter.name?.lexeme != 'context') continue;
        final type = parameter.type;
        if (type == null ||
            (type is NamedType && type.name.lexeme == 'BuildContext')) {
          return true;
        }
      }
    }
    if (current is MethodDeclaration && current.isStatic) return false;
    if (current is FieldDeclaration && current.isStatic) return false;
    if (current is ClassDeclaration) {
      return current.extendsClause?.superclass.name.lexeme == 'State';
    }
  }
  return false;
}

/// Whether [suggestion] can replace [node] without breaking the code.
///
/// A `static const` token can be used anywhere. A token read through an
/// instance (a `ThemeExtension` field) is not a constant and may need a
/// `BuildContext`.
bool canApply(TokenSuggestion suggestion, AstNode node) {
  final entry = suggestion.entry;
  if (!entry.isInstanceField) return true;
  if (!allowsNonConstant(node)) return false;
  return !entry.needsContext || hasBuildContext(node);
}
