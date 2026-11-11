import '../config/config_loader.dart';
import '../config/rule_id.dart';
import 'color_detector.dart';
import 'component_detector.dart';
import 'detector.dart';
import 'radius_detector.dart';
import 'shadow_detector.dart';
import 'spacing_detector.dart';
import 'typography_detector.dart';

/// Creates the detectors for the rules of a project.
final class Detectors {
  const Detectors._();

  /// Creates the detector that implements [rule].
  static Detector forRule(RuleId rule, ProjectConfig project) => switch (rule) {
    RuleId.avoidRawColor => ColorDetector(project),
    RuleId.avoidMagicSpacing => SpacingDetector(project),
    RuleId.avoidRawRadius => RadiusDetector(project),
    RuleId.avoidInlineTextStyle => TypographyDetector(project),
    RuleId.avoidRawShadow => ShadowDetector(project),
    RuleId.preferDesignSystemComponent => ComponentDetector(project),
  };

  /// Creates the detectors of every rule that has something to enforce.
  static List<Detector> active(ProjectConfig project) => [
    for (final rule in RuleId.values)
      if (project.isRuleActive(rule)) forRule(rule, project),
  ];
}
