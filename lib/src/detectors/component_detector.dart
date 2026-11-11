import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';

import '../config/rule_id.dart';
import '../tokens/token_index.dart';
import '../tokens/token_value.dart';
import 'detector.dart';
import 'element_checks.dart';
import 'finding.dart';

/// Detects Flutter widgets that have a design-system replacement.
///
/// The widget is matched through its resolved element, so a class of the same
/// name declared in the user's own code is never reported.
final class ComponentDetector extends Detector {
  /// Creates the detector.
  ComponentDetector(super.project);

  @override
  RuleId get rule => RuleId.preferDesignSystemComponent;

  @override
  Set<NodeKind> get nodeKinds => const {NodeKind.instanceCreation};

  @override
  void check(AstNode node, FindingSink report) {
    if (node is! InstanceCreationExpression) return;
    final type = node.constructorName.type;
    final element = type.element;
    if (element is! ClassElement || !isDeclaredInFlutter(element)) return;
    final replacement = config.components[element.name];
    if (replacement == null) return;
    if (isInsideTokenClass(node)) return;
    report(
      Finding(
        rule: rule,
        node: type,
        raw: element.name ?? type.name.lexeme,
        suggestions: [
          TokenSuggestion(
            entry: TokenEntry(
              category: DesignCategory.component,
              className: replacement.replacement,
              name: '',
              value: const NumberValue(0),
              importUri: replacement.import,
            ),
            distance: 0,
            offset: type.offset,
            length: type.length,
            replacement: replacement.replacement,
            importUri: replacement.import,
          ),
        ],
      ),
    );
  }
}
