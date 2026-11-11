import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import 'detector.dart';

/// Forwards the nodes a [Detector] inspects to [Detector.check].
///
/// Used by the analyzer plugin, which registers it for the node kinds the
/// detector declares.
final class DetectorVisitor extends SimpleAstVisitor<void> {
  /// Creates a visitor that calls [detector] for each node and passes the
  /// findings to [report].
  DetectorVisitor(this.detector, this.report);

  /// The detector that does the work.
  final Detector detector;

  /// Receives the findings.
  final FindingSink report;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) =>
      detector.check(node, report);

  @override
  void visitMethodInvocation(MethodInvocation node) =>
      detector.check(node, report);

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) =>
      detector.check(node, report);

  @override
  void visitPropertyAccess(PropertyAccess node) => detector.check(node, report);

  @override
  void visitIndexExpression(IndexExpression node) =>
      detector.check(node, report);

  @override
  void visitListLiteral(ListLiteral node) => detector.check(node, report);
}

/// Runs a set of detectors over a whole syntax tree.
///
/// Used by the coverage command.
final class DetectorWalker extends RecursiveAstVisitor<void> {
  /// Creates a walker that runs [detectors] and passes findings to [report].
  DetectorWalker(this.detectors, this.report);

  /// The detectors to run.
  final List<Detector> detectors;

  /// Receives the findings.
  final FindingSink report;

  void _check(AstNode node) {
    for (final detector in detectors) {
      detector.check(node, report);
    }
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _check(node);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _check(node);
    super.visitMethodInvocation(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    _check(node);
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    _check(node);
    super.visitPropertyAccess(node);
  }

  @override
  void visitIndexExpression(IndexExpression node) {
    _check(node);
    super.visitIndexExpression(node);
  }

  @override
  void visitListLiteral(ListLiteral node) {
    _check(node);
    super.visitListLiteral(node);
  }
}
