import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'rule_id.dart';

/// The keys the configuration accepts, section by section.
///
/// The JSON schema in `doc/design_token_lints.schema.json` describes the same
/// keys; a test checks that the two agree.
abstract final class ConfigKeys {
  /// Keys of the `design_token_lints` section itself.
  static const topLevel = {
    'design_system',
    'tokens',
    'allow',
    'matching',
    'components',
    'exclude',
    'rules',
    'design_tokens',
  };

  /// Keys of `design_tokens`.
  static const designTokens = {'file', 'map'};

  /// Keys of each entry under `design_tokens.map`.
  static const designTokenGroup = {'group', 'names'};

  /// Keys of `design_system`.
  static const designSystem = {'paths', 'packages'};

  /// Keys of each entry under `tokens`.
  static const tokenSource = {'class', 'file', 'instance', 'access', 'import'};

  /// Keys of `allow`.
  static const allow = {'color', 'spacing', 'radius', 'icon_size', 'elevation'};

  /// Keys of `matching`.
  static const matching = {
    'spacing_tolerance',
    'radius_tolerance',
    'icon_size_tolerance',
    'elevation_tolerance',
    'color_delta_e',
  };

  /// Keys of each entry under `components`.
  static const component = {'replacement', 'import'};

  /// Keys of each entry under `rules`.
  static const rule = {'exclude'};
}

/// Where a [DtlConfig] was read from.
enum ConfigSource {
  /// No configuration was found.
  none,

  /// The top-level `design_token_lints:` section of `analysis_options.yaml`.
  analysisOptions,

  /// A standalone `design_token_lints.yaml`.
  standalone,
}

/// How serious a [ConfigIssue] is.
enum ConfigIssueSeverity {
  /// The configuration is usable, but something was ignored.
  warning,

  /// Part of the configuration (or all of it) could not be used.
  error,
}

/// A problem found while reading or validating the configuration.
class ConfigIssue {
  /// Creates an issue.
  const ConfigIssue(this.severity, this.message);

  /// How serious the issue is.
  final ConfigIssueSeverity severity;

  /// A human-readable description, including the offending key.
  final String message;

  @override
  String toString() => '${severity.name}: $message';
}

/// The class that holds the tokens of one [DesignCategory].
class TokenSource {
  /// Creates a token source.
  const TokenSource({
    required this.className,
    required this.file,
    this.instance,
    this.access,
    this.import,
  });

  /// The name of the class, for example `AppColors`.
  final String className;

  /// A path relative to the configuration directory, or a `package:` URI.
  final String file;

  /// For a `ThemeExtension` (or any class whose tokens are instance fields),
  /// the `static const` instance whose constructor arguments are the token
  /// values, for example `light`. `null` for a class of `static const`
  /// tokens.
  final String? instance;

  /// How code reads a token of an [instance]-based class, with `{name}` for
  /// the field, for example `context.palette.{name}`.
  final String? access;

  /// The library a fix imports to make [access] work, instead of the token
  /// file.
  final String? import;

  /// The default [access] of an [instance]-based class.
  static String defaultAccess(String className) =>
      'Theme.of(context).extension<$className>()!.{name}';
}

/// How a category of Dart tokens maps to a group of a design tokens file.
final class DesignTokenGroup {
  /// Creates a mapping.
  const DesignTokenGroup({required this.group, this.names = const {}});

  /// The dotted path of the group, for example `color` or `color.brand`.
  final String group;

  /// Dart member names for design token paths (relative to [group]) whose
  /// camelCase name is not wanted or not a valid identifier, for example
  /// `{'4': 'xs'}`.
  final Map<String, String> names;
}

/// The design tokens file to compare the Dart tokens with
/// (`design_token_lints check-tokens`).
class DesignTokensSource {
  /// Creates a source.
  const DesignTokensSource({required this.file, required this.groups});

  /// A path relative to the configuration directory.
  final String file;

  /// The group of the file each category is compared with.
  final Map<DesignCategory, DesignTokenGroup> groups;
}

/// A raw widget and the design-system widget that replaces it.
class ComponentReplacement {
  /// Creates a replacement.
  const ComponentReplacement({required this.replacement, this.import});

  /// The class name to use instead, for example `AppButton`.
  final String replacement;

  /// The library that declares [replacement], added to the file by the fix.
  final String? import;
}

/// The parsed `design_token_lints` configuration.
class DtlConfig {
  DtlConfig._({
    required this.rootPath,
    required this.source,
    required this.issues,
    this.designSystemPaths = const [],
    this.designSystemPackages = const {},
    this.tokens = const {},
    this.allowColorValues = const {},
    this.allowColorNames = const {},
    this.allowSpacing = const {},
    this.allowRadius = const {},
    this.allowIconSize = const {},
    this.allowElevation = const {},
    this.spacingTolerance = 0,
    this.radiusTolerance = 0,
    this.iconSizeTolerance = 0,
    this.elevationTolerance = 0,
    this.colorDeltaE = 0,
    this.components = const {},
    this.exclude = const [],
    this.ruleExcludes = const {},
    this.designTokens,
  }) : _designSystemGlobs = _globs(designSystemPaths),
       _excludeGlobs = _globs(exclude),
       _ruleGlobs = {
         for (final entry in ruleExcludes.entries)
           entry.key: _globs(entry.value),
       };

  /// A configuration that enforces nothing.
  factory DtlConfig.none({
    String rootPath = '',
    List<ConfigIssue> issues = const [],
  }) => DtlConfig._(
    rootPath: rootPath,
    source: ConfigSource.none,
    issues: issues,
  );

  /// Parses an already-decoded YAML document.
  ///
  /// Never throws: invalid input produces [ConfigIssue]s and, if nothing is
  /// usable, a configuration whose [isPresent] is `false`.
  factory DtlConfig.parse(
    Object? yaml, {
    required String rootPath,
    required ConfigSource source,
  }) {
    final issues = <ConfigIssue>[];
    if (yaml is! Map) {
      issues.add(
        const ConfigIssue(
          ConfigIssueSeverity.error,
          'The design_token_lints configuration must be a mapping.',
        ),
      );
      return DtlConfig.none(rootPath: rootPath, issues: issues);
    }
    final reader = _Reader(issues);
    reader.unknownKeys(yaml, ConfigKeys.topLevel, 'design_token_lints');

    final designSystem = reader.map(yaml['design_system'], 'design_system');
    reader.unknownKeys(designSystem, ConfigKeys.designSystem, 'design_system');
    final tokens = _readTokens(reader, yaml['tokens']);
    final allow = reader.map(yaml['allow'], 'allow');
    reader.unknownKeys(allow, ConfigKeys.allow, 'allow');
    final matching = reader.map(yaml['matching'], 'matching');
    reader.unknownKeys(matching, ConfigKeys.matching, 'matching');

    final colorValues = <int>{};
    final colorNames = <String>{};
    for (final entry in reader.list(allow['color'], 'allow.color')) {
      if (entry is int) {
        colorValues.add(entry);
      } else if (entry is String && entry.startsWith('Colors.')) {
        colorNames.add(
          entry.substring('Colors.'.length).replaceAll('.shade', '.'),
        );
      } else if (entry is String && int.tryParse(entry) != null) {
        colorValues.add(int.parse(entry));
      } else {
        reader.warn(
          'allow.color: "$entry" is not a hex value or a Colors.<name>.',
        );
      }
    }

    return DtlConfig._(
      rootPath: rootPath,
      source: source,
      issues: issues,
      designSystemPaths: reader.strings(
        designSystem['paths'],
        'design_system.paths',
      ),
      designSystemPackages: reader
          .strings(designSystem['packages'], 'design_system.packages')
          .toSet(),
      tokens: tokens,
      allowColorValues: colorValues,
      allowColorNames: colorNames,
      allowSpacing: reader.numbers(allow['spacing'], 'allow.spacing'),
      allowRadius: reader.numbers(allow['radius'], 'allow.radius'),
      allowIconSize: reader.numbers(allow['icon_size'], 'allow.icon_size'),
      allowElevation: reader.numbers(allow['elevation'], 'allow.elevation'),
      spacingTolerance: reader.number(
        matching['spacing_tolerance'],
        'matching.spacing_tolerance',
      ),
      radiusTolerance: reader.number(
        matching['radius_tolerance'],
        'matching.radius_tolerance',
      ),
      iconSizeTolerance: reader.number(
        matching['icon_size_tolerance'],
        'matching.icon_size_tolerance',
      ),
      elevationTolerance: reader.number(
        matching['elevation_tolerance'],
        'matching.elevation_tolerance',
      ),
      colorDeltaE: reader.number(
        matching['color_delta_e'],
        'matching.color_delta_e',
      ),
      components: _readComponents(reader, yaml['components']),
      exclude: reader.strings(yaml['exclude'], 'exclude'),
      ruleExcludes: _readRuleExcludes(reader, yaml['rules']),
      designTokens: _readDesignTokens(reader, yaml['design_tokens']),
    );
  }

  /// The directory that contains the configuration; relative paths in the
  /// configuration are resolved against it.
  final String rootPath;

  /// Where the configuration was read from.
  final ConfigSource source;

  /// Problems found while reading the configuration.
  final List<ConfigIssue> issues;

  /// Globs of files in which raw values legitimately live.
  final List<String> designSystemPaths;

  /// Package names whose files are exempt.
  final Set<String> designSystemPackages;

  /// The token class of each configured category.
  final Map<DesignCategory, TokenSource> tokens;

  /// ARGB values that are always allowed.
  final Set<int> allowColorValues;

  /// `Colors.<name>` members that are always allowed.
  final Set<String> allowColorNames;

  /// Spacing literals that are always allowed.
  final Set<double> allowSpacing;

  /// Radius literals that are always allowed.
  final Set<double> allowRadius;

  /// Icon size literals that are always allowed.
  final Set<double> allowIconSize;

  /// Elevation literals that are always allowed.
  final Set<double> allowElevation;

  /// Largest spacing difference, in logical pixels, offered as "nearest".
  final double spacingTolerance;

  /// Largest radius difference, in logical pixels, offered as "nearest".
  final double radiusTolerance;

  /// Largest icon size difference, in logical pixels, offered as "nearest".
  final double iconSizeTolerance;

  /// Largest elevation difference offered as "nearest".
  final double elevationTolerance;

  /// Largest CIEDE2000 distance offered as "nearest"; `0` disables it.
  final double colorDeltaE;

  /// Raw widget class name to its replacement.
  final Map<String, ComponentReplacement> components;

  /// Globs of files no rule applies to.
  final List<String> exclude;

  /// Globs of files a single rule skips.
  final Map<RuleId, List<String>> ruleExcludes;

  /// The design tokens file to compare with, if any.
  final DesignTokensSource? designTokens;

  final List<Glob> _designSystemGlobs;
  final List<Glob> _excludeGlobs;
  final Map<RuleId, List<Glob>> _ruleGlobs;

  /// Whether any configuration was found and is usable.
  bool get isPresent => source != ConfigSource.none;

  /// Whether any issue is an error.
  bool get hasErrors =>
      issues.any((issue) => issue.severity == ConfigIssueSeverity.error);

  /// Whether the rules of [category] have anything to enforce.
  bool isCategoryConfigured(DesignCategory category) {
    if (!isPresent) return false;
    return category == DesignCategory.component
        ? components.isNotEmpty
        : tokens.containsKey(category);
  }

  /// Whether [relativePath] (relative to [rootPath], using `/`) is part of the
  /// design system.
  bool isDesignSystemPath(String relativePath) =>
      _designSystemGlobs.any((glob) => glob.matches(relativePath));

  /// Whether [relativePath] is excluded for every rule or for [rule].
  bool isExcluded(String relativePath, [RuleId? rule]) {
    if (_excludeGlobs.any((glob) => glob.matches(relativePath))) return true;
    if (rule == null) return false;
    final globs = _ruleGlobs[rule];
    return globs != null && globs.any((glob) => glob.matches(relativePath));
  }

  /// Whether the [colorValue] or `Colors.<colorName>` is on the allow-list.
  bool isColorAllowed({int? colorValue, String? colorName}) =>
      (colorValue != null && allowColorValues.contains(colorValue)) ||
      (colorName != null && allowColorNames.contains(colorName));

  static List<Glob> _globs(List<String> patterns) => [
    for (final pattern in patterns) Glob(pattern, context: p.posix),
  ];

  static Map<DesignCategory, TokenSource> _readTokens(
    _Reader reader,
    Object? raw,
  ) {
    final result = <DesignCategory, TokenSource>{};
    final map = reader.map(raw, 'tokens');
    for (final entry in map.entries) {
      final key = '${entry.key}';
      final category = DesignCategory.fromKey(key);
      if (category == null || !category.isToken) {
        reader.warn(
          'tokens.$key: unknown category. Expected one of '
          '${DesignCategory.values.where((c) => c.isToken).map((c) => c.key).join(', ')}.',
        );
        continue;
      }
      final source = reader.map(entry.value, 'tokens.$key');
      final className = source['class'];
      final file = source['file'];
      if (className is! String || file is! String) {
        reader.error('tokens.$key: both "class" and "file" must be strings.');
        continue;
      }
      reader.unknownKeys(source, ConfigKeys.tokenSource, 'tokens.$key');
      final instance = source['instance'];
      final access = source['access'];
      final import = source['import'];
      if (instance != null && instance is! String) {
        reader.error('tokens.$key: "instance" must be a string.');
        continue;
      }
      if ((access != null && access is! String) ||
          (import != null && import is! String)) {
        reader.error('tokens.$key: "access" and "import" must be strings.');
        continue;
      }
      if (instance == null && (access != null || import != null)) {
        reader.warn(
          'tokens.$key: "access" and "import" apply only with "instance"; '
          'they are ignored.',
        );
      }
      if (access is String && !access.contains('{name}')) {
        reader.error('tokens.$key: "access" must contain {name}.');
        continue;
      }
      result[category] = TokenSource(
        className: className,
        file: file,
        instance: instance as String?,
        access: instance == null
            ? null
            : (access as String?) ?? TokenSource.defaultAccess(className),
        import: instance == null ? null : import as String?,
      );
    }
    return result;
  }

  static DesignTokensSource? _readDesignTokens(_Reader reader, Object? raw) {
    if (raw == null) return null;
    final section = reader.map(raw, 'design_tokens');
    reader.unknownKeys(section, ConfigKeys.designTokens, 'design_tokens');
    final file = section['file'];
    if (file is! String) {
      reader.error('design_tokens: "file" must be a string.');
      return null;
    }
    final groups = <DesignCategory, DesignTokenGroup>{};
    for (final entry
        in reader.map(section['map'], 'design_tokens.map').entries) {
      final key = '${entry.key}';
      final at = 'design_tokens.map.$key';
      final category = DesignCategory.fromKey(key);
      if (category == null || !category.isToken) {
        reader.warn('$at: unknown category.');
        continue;
      }
      final mapping = reader.map(entry.value, at);
      reader.unknownKeys(mapping, ConfigKeys.designTokenGroup, at);
      final group = mapping['group'];
      if (group is! String) {
        reader.error('$at: "group" must be a string.');
        continue;
      }
      final names = <String, String>{};
      for (final MapEntry(key: path, value: name)
          in reader.map(mapping['names'], '$at.names').entries) {
        if (name is String) {
          names['$path'] = name;
        } else {
          reader.warn('$at.names.$path: "$name" is not a string.');
        }
      }
      groups[category] = DesignTokenGroup(group: group, names: names);
    }
    if (groups.isEmpty) {
      reader.warn('design_tokens: "map" names no category to compare.');
    }
    return DesignTokensSource(file: file, groups: groups);
  }

  static Map<String, ComponentReplacement> _readComponents(
    _Reader reader,
    Object? raw,
  ) {
    final result = <String, ComponentReplacement>{};
    final map = reader.map(raw, 'components');
    for (final entry in map.entries) {
      final name = '${entry.key}';
      final value = reader.map(entry.value, 'components.$name');
      final replacement = value['replacement'];
      final import = value['import'];
      if (replacement is! String) {
        reader.error('components.$name: "replacement" must be a string.');
        continue;
      }
      if (import != null && import is! String) {
        reader.error('components.$name: "import" must be a string.');
        continue;
      }
      reader.unknownKeys(value, ConfigKeys.component, 'components.$name');
      result[name] = ComponentReplacement(
        replacement: replacement,
        import: import as String?,
      );
    }
    return result;
  }

  static Map<RuleId, List<String>> _readRuleExcludes(
    _Reader reader,
    Object? raw,
  ) {
    final result = <RuleId, List<String>>{};
    final map = reader.map(raw, 'rules');
    for (final entry in map.entries) {
      final code = '${entry.key}';
      final rule = RuleId.fromCode(code);
      if (rule == null) {
        reader.warn('rules.$code: unknown rule.');
        continue;
      }
      final options = reader.map(entry.value, 'rules.$code');
      reader.unknownKeys(options, ConfigKeys.rule, 'rules.$code');
      result[rule] = reader.strings(options['exclude'], 'rules.$code.exclude');
    }
    return result;
  }
}

class _Reader {
  _Reader(this.issues);

  final List<ConfigIssue> issues;

  void warn(String message) =>
      issues.add(ConfigIssue(ConfigIssueSeverity.warning, message));

  void error(String message) =>
      issues.add(ConfigIssue(ConfigIssueSeverity.error, message));

  void unknownKeys(Map<Object?, Object?> map, Set<String> known, String at) {
    for (final key in map.keys) {
      if (!known.contains(key)) {
        warn('$at: unknown key "$key".');
      }
    }
  }

  Map<Object?, Object?> map(Object? value, String at) {
    if (value == null) return const {};
    if (value is Map) return value.cast<Object?, Object?>();
    error('$at: expected a mapping.');
    return const {};
  }

  List<Object?> list(Object? value, String at) {
    if (value == null) return const [];
    if (value is YamlList || value is List) return (value as List).cast();
    error('$at: expected a list.');
    return const [];
  }

  List<String> strings(Object? value, String at) {
    final result = <String>[];
    for (final item in list(value, at)) {
      if (item is String) {
        result.add(item);
      } else {
        warn('$at: "$item" is not a string.');
      }
    }
    return result;
  }

  Set<double> numbers(Object? value, String at) {
    final result = <double>{};
    for (final item in list(value, at)) {
      if (item is num) {
        result.add(item.toDouble());
      } else {
        warn('$at: "$item" is not a number.');
      }
    }
    return result;
  }

  double number(Object? value, String at) {
    if (value == null) return 0;
    if (value is num && value >= 0) return value.toDouble();
    error('$at: expected a non-negative number.');
    return 0;
  }
}
