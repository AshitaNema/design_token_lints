import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/error/error.dart';

import '../config/config_loader.dart';
import '../config/rule_id.dart';
import '../detectors/detector.dart';
import '../detectors/detectors.dart';
import '../detectors/finding.dart';
import '../detectors/node_visitors.dart';

/// The diagnostic codes of the rules.
abstract final class DtlCodes {
  /// `avoid_raw_color`.
  static const avoidRawColor = LintCode(
    'avoid_raw_color',
    "Raw color '{0}' bypasses the design system.",
    correctionMessage: 'Try using {1}.',
    severity: DiagnosticSeverity.WARNING,
  );

  /// `avoid_magic_spacing`.
  static const avoidMagicSpacing = LintCode(
    'avoid_magic_spacing',
    "Magic spacing value '{0}'.",
    correctionMessage: 'Try using {1}.',
    severity: DiagnosticSeverity.WARNING,
  );

  /// `avoid_raw_radius`.
  static const avoidRawRadius = LintCode(
    'avoid_raw_radius',
    "Raw corner radius '{0}'.",
    correctionMessage: 'Try using {1}.',
    severity: DiagnosticSeverity.WARNING,
  );

  /// `avoid_inline_text_style`.
  static const avoidInlineTextStyle = LintCode(
    'avoid_inline_text_style',
    'Inline TextStyle bypasses the design system.',
    correctionMessage: 'Try using {1}.',
    severity: DiagnosticSeverity.WARNING,
  );

  /// `avoid_raw_shadow`.
  static const avoidRawShadow = LintCode(
    'avoid_raw_shadow',
    'Hand-written shadow bypasses the design system.',
    correctionMessage: 'Try using {1}.',
  );

  /// `prefer_design_system_component`.
  static const preferDesignSystemComponent = LintCode(
    'prefer_design_system_component',
    "'{0}' has a design-system replacement.",
    correctionMessage: 'Try using {1}.',
    severity: DiagnosticSeverity.WARNING,
  );

  /// The code reported by [rule].
  static LintCode of(RuleId rule) => switch (rule) {
    RuleId.avoidRawColor => avoidRawColor,
    RuleId.avoidMagicSpacing => avoidMagicSpacing,
    RuleId.avoidRawRadius => avoidRawRadius,
    RuleId.avoidInlineTextStyle => avoidInlineTextStyle,
    RuleId.avoidRawShadow => avoidRawShadow,
    RuleId.preferDesignSystemComponent => preferDesignSystemComponent,
  };
}

/// An analysis rule that runs one [Detector] and reports its findings.
final class DesignTokenRule extends AnalysisRule {
  /// Creates the rule for [id].
  DesignTokenRule(this.id, {ConfigLoader? loader})
    : _loader = loader ?? ConfigLoader.shared,
      super(name: id.code, description: _descriptions[id]!);

  static const _descriptions = {
    RuleId.avoidRawColor:
        'Flags raw colors so that colors come from the design system.',
    RuleId.avoidMagicSpacing:
        'Flags numeric spacing literals so that spacing comes from the '
        'design system.',
    RuleId.avoidRawRadius:
        'Flags numeric corner radii so that radii come from the design '
        'system.',
    RuleId.avoidInlineTextStyle:
        'Flags inline TextStyle constructors so that text styles come from '
        'the design system.',
    RuleId.avoidRawShadow:
        'Flags hand-written shadows so that shadows come from the design '
        'system.',
    RuleId.preferDesignSystemComponent:
        'Flags raw widgets that the design system replaces with its own.',
  };

  /// The rule this instance implements.
  final RuleId id;

  final ConfigLoader _loader;

  @override
  LintCode get diagnosticCode => DtlCodes.of(id);

  @override
  bool get canUseParsedResult =>
      id != RuleId.avoidRawColor && id != RuleId.preferDesignSystemComponent;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final lookup = _loader.lookup(context.definingUnit.file);
    final project = lookup.project;
    if (!project.isRuleActive(id)) return;

    final detector = Detectors.forRule(id, project);
    final exemptions = <String, bool>{};

    bool isChecked(RuleContext context) {
      final unit = context.currentUnit;
      if (unit == null) return false;
      return exemptions.putIfAbsent(
        unit.file.path,
        () =>
            project.exemptionFor(
              unit.file.path,
              packageName: lookup.packageName,
              content: unit.content,
              rule: id,
            ) ==
            null,
      );
    }

    void report(Finding finding) =>
        reportAtNode(finding.node, arguments: finding.messageArguments);

    final visitor = DetectorVisitor(detector, (finding) {
      if (isChecked(context)) report(finding);
    });
    for (final kind in detector.nodeKinds) {
      switch (kind) {
        case NodeKind.instanceCreation:
          registry.addInstanceCreationExpression(this, visitor);
        case NodeKind.methodInvocation:
          registry.addMethodInvocation(this, visitor);
        case NodeKind.prefixedIdentifier:
          registry.addPrefixedIdentifier(this, visitor);
        case NodeKind.propertyAccess:
          registry.addPropertyAccess(this, visitor);
        case NodeKind.indexExpression:
          registry.addIndexExpression(this, visitor);
        case NodeKind.listLiteral:
          registry.addListLiteral(this, visitor);
      }
    }
  }
}
