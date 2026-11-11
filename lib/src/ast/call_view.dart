import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';

/// A uniform view of a constructor-style call.
///
/// Before resolution the parser reports `EdgeInsets.all(8)` as a
/// [MethodInvocation]; after resolution it is an [InstanceCreationExpression].
/// Detectors and the token evaluator work on both through this view.
final class CallView {
  const CallView._({
    required this.node,
    required this.typeName,
    required this.constructorName,
    required this.arguments,
    required this.typeNode,
    required this.keyword,
  });

  /// The call expression itself.
  final Expression node;

  /// The class name, for example `EdgeInsets`.
  final String typeName;

  /// The named constructor (`all`), or `null` for the default constructor.
  final String? constructorName;

  /// The call arguments.
  final ArgumentList arguments;

  /// The node that spells the type name, used to replace just the type.
  final AstNode typeNode;

  /// The `const` / `new` keyword, if any.
  final Token? keyword;

  /// Returns the call view of [node], or `null` if it is not a
  /// constructor-style call.
  static CallView? of(AstNode? node) {
    if (node is InstanceCreationExpression) {
      return CallView._(
        node: node,
        typeName: node.constructorName.type.name.lexeme,
        constructorName: node.constructorName.name?.name,
        arguments: node.argumentList,
        typeNode: node.constructorName.type,
        keyword: node.keyword,
      );
    }
    if (node is MethodInvocation) {
      final target = node.target;
      if (target == null) {
        return CallView._(
          node: node,
          typeName: node.methodName.name,
          constructorName: null,
          arguments: node.argumentList,
          typeNode: node.methodName,
          keyword: null,
        );
      }
      if (target is SimpleIdentifier) {
        return CallView._(
          node: node,
          typeName: target.name,
          constructorName: node.methodName.name,
          arguments: node.argumentList,
          typeNode: target,
          keyword: null,
        );
      }
    }
    return null;
  }

  /// The positional arguments, in order.
  List<Expression> get positional => [
    for (final argument in arguments.arguments)
      if (argument is Expression) argument,
  ];

  /// The named arguments by name.
  Map<String, Expression> get named => {
    for (final argument in arguments.arguments)
      if (argument is NamedArgument)
        argument.name.lexeme: argument.argumentExpression,
  };

  /// Whether this call is `Type` or `Type.constructor`.
  bool matches(String type, [String? constructor]) =>
      typeName == type && constructorName == constructor;
}
