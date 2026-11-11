import 'package:analyzer/dart/ast/ast.dart';

import '../config/config.dart';
import '../config/config_loader.dart';
import '../config/rule_id.dart';
import '../tokens/token_index.dart';
import 'finding.dart';

/// Receives the findings of a detector.
typedef FindingSink = void Function(Finding finding);

/// The kinds of syntax nodes a detector inspects.
enum NodeKind {
  /// `InstanceCreationExpression`.
  instanceCreation,

  /// `MethodInvocation`; constructor calls look like this before resolution.
  methodInvocation,

  /// `PrefixedIdentifier`, such as `Colors.red`.
  prefixedIdentifier,

  /// `PropertyAccess`, such as `Colors.red.shade100`.
  propertyAccess,

  /// `IndexExpression`, such as `Colors.red[100]`.
  indexExpression,

  /// `ListLiteral`.
  listLiteral,
}

/// Finds the places that one rule reports.
///
/// Detectors are pure functions of the syntax tree and the project
/// configuration. The analyzer plugin and the coverage command both run the
/// same detectors, so they always agree.
abstract base class Detector {
  /// Creates a detector for [project].
  Detector(this.project);

  /// The configuration and tokens the detector enforces.
  final ProjectConfig project;

  /// The rule this detector implements.
  RuleId get rule;

  /// The node kinds [check] needs to be called with.
  Set<NodeKind> get nodeKinds;

  /// The configuration.
  DtlConfig get config => project.config;

  /// The discovered tokens.
  TokenIndex get index => project.index;

  /// Inspects [node] and reports any findings to [report].
  void check(AstNode node, FindingSink report);

  /// Whether [node] is declared inside one of the configured token classes.
  bool isInsideTokenClass(AstNode node) {
    final declaration = node.thisOrAncestorOfType<ClassDeclaration>();
    return declaration != null &&
        index.tokenClassNames.contains(declaration.namePart.typeName.lexeme);
  }
}
