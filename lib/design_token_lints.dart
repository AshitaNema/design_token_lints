/// Enforce your Flutter design system with analyzer lints, quick fixes and a
/// coverage report.
///
/// The analyzer plugin is installed through `analysis_options.yaml`; see the
/// package README. This library exposes the pieces behind it for tools that
/// want to reuse them: the configuration model, the token index, the
/// detectors that the rules and the `coverage` command share, and the
/// coverage report.
library;

export 'src/config/config.dart'
    show
        ComponentReplacement,
        ConfigIssue,
        ConfigIssueSeverity,
        ConfigSource,
        DtlConfig,
        TokenSource;
export 'src/config/config_loader.dart'
    show ConfigLoader, ConfigLookup, ProjectConfig;
export 'src/config/exemptions.dart' show Exemption, isGeneratedFile;
export 'src/config/rule_id.dart' show DesignCategory, RuleId;
export 'src/detectors/detector.dart' show Detector, FindingSink, NodeKind;
export 'src/detectors/detectors.dart' show Detectors;
export 'src/detectors/finding.dart' show Finding, TokenSuggestion;
export 'src/detectors/node_visitors.dart' show DetectorVisitor, DetectorWalker;
export 'src/report/coverage_report.dart'
    show CategoryStats, CoverageReport, FileReport, ReportFinding;
export 'src/report/project_analyzer.dart' show AnalysisOutcome, ProjectAnalyzer;
export 'src/report/renderers.dart'
    show ReportFormat, jsonSchemaVersion, markdownMarker, renderReport;
export 'src/tokens/nearest_token_matcher.dart'
    show NearestTokenMatcher, TokenMatch;
export 'src/tokens/token_index.dart' show SkippedToken, TokenEntry, TokenIndex;
export 'src/tokens/token_value.dart'
    show
        BorderRadiusValue,
        ColorValue,
        NumberValue,
        RadiusValue,
        ShadowLayer,
        ShadowValue,
        TextStyleValue,
        TokenValue;
