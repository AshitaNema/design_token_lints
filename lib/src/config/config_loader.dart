import 'package:analyzer/file_system/file_system.dart';
import 'package:yaml/yaml.dart';

import '../tokens/token_index.dart';
import 'baseline.dart';
import 'config.dart';
import 'exemptions.dart';
import 'package_locator.dart';
import 'rule_id.dart';

/// A configuration together with the tokens it describes.
final class ProjectConfig {
  /// Creates a project configuration.
  ProjectConfig({
    required this.config,
    required this.index,
    required this.provider,
    Baseline? baseline,
  }) : baseline = baseline ?? Baseline.empty;

  /// A project without configuration; every rule stays silent.
  factory ProjectConfig.none(ResourceProvider provider, {DtlConfig? config}) =>
      ProjectConfig(
        config: config ?? DtlConfig.none(),
        index: TokenIndex.empty,
        provider: provider,
      );

  /// The parsed configuration.
  final DtlConfig config;

  /// The discovered tokens.
  final TokenIndex index;

  /// The file system the project was read from.
  final ResourceProvider provider;

  /// The findings the project has accepted.
  final Baseline baseline;

  /// The path of [path] relative to the configuration, with `/` separators,
  /// as used in the baseline.
  String relativePath(String path) =>
      relativePosix(provider.pathContext, config.rootPath, path);

  /// Whether any configuration is in effect.
  bool get isActive => config.isPresent;

  /// Every problem with the configuration and the token files.
  List<ConfigIssue> get issues => [
    ...config.issues,
    ...index.issues,
    ...baseline.issues,
  ];

  /// Whether [rule] has anything to enforce.
  bool isRuleActive(RuleId rule) {
    if (!config.isPresent) return false;
    final category = rule.category;
    if (!config.isCategoryConfigured(category)) return false;
    return category == DesignCategory.component || index.hasCategory(category);
  }

  /// Returns why [path] is not checked by [rule] (or by any rule when [rule]
  /// is `null`), or `null` if it is checked.
  ///
  /// [packageName] is the package that contains the file; [content], when
  /// available, is used to recognize generated files.
  Exemption? exemptionFor(
    String path, {
    String? packageName,
    String? content,
    RuleId? rule,
  }) {
    if (index.tokenFilePaths.contains(path)) return Exemption.tokenFile;
    if (isGeneratedFile(path, content)) return Exemption.generated;
    if (packageName != null &&
        config.designSystemPackages.contains(packageName)) {
      return Exemption.designSystemPackage;
    }
    final relative = relativePosix(provider.pathContext, config.rootPath, path);
    if (config.isDesignSystemPath(relative)) return Exemption.designSystemPath;
    if (config.isExcluded(relative)) return Exemption.excluded;
    if (rule != null && config.isExcluded(relative, rule)) {
      return Exemption.ruleExcluded;
    }
    return null;
  }
}

/// The result of looking up the configuration that applies to a file.
final class ConfigLookup {
  /// Creates a lookup result.
  const ConfigLookup({required this.project, required this.packageName});

  /// The configuration and tokens that apply.
  final ProjectConfig project;

  /// The name of the package that contains the file, or `''`.
  final String packageName;
}

/// Finds, reads and caches the configuration for analyzed files.
///
/// The configuration is looked up from the package that contains the file; a
/// package that is a workspace member falls back to the workspace root. Results
/// are cached per configuration directory and invalidated when the
/// configuration file, `analysis_options.yaml` or any token file changes.
final class ConfigLoader {
  /// Creates a loader with its own cache.
  ConfigLoader();

  /// The loader used by the analyzer plugin.
  static final ConfigLoader shared = ConfigLoader();

  final Expando<Map<String, _CacheEntry>> _caches = Expando();

  /// Returns the configuration that applies to [file].
  ConfigLookup lookup(File file) {
    final provider = file.provider;
    final package = PackageLocator.nearest(file);
    if (package == null) {
      return ConfigLookup(
        project: ProjectConfig.none(provider),
        packageName: '',
      );
    }
    var project = load(package.root);
    if (!project.isActive) {
      final workspace = PackageLocator.workspaceRootOf(package);
      if (workspace != null) {
        final candidate = load(workspace.root);
        if (candidate.isActive) project = candidate;
      }
    }
    return ConfigLookup(project: project, packageName: package.name);
  }

  /// Loads the configuration stored in [root], using the cache when the
  /// files have not changed.
  ProjectConfig load(Folder root) {
    final provider = root.provider;
    final cache = _caches[provider] ??= {};
    final cached = cache[root.path];
    if (cached != null && cached.isFresh(provider)) return cached.project;
    final project = _read(root);
    final watched = <String>{
      childFile(root, 'design_token_lints.yaml').path,
      childFile(root, 'analysis_options.yaml').path,
      childFile(root, baselineFileName).path,
      ...project.index.watchedPaths,
    };
    cache[root.path] = _CacheEntry(project, {
      for (final path in watched) path: _stamp(provider, path),
    });
    return project;
  }

  ProjectConfig _read(Folder root) {
    final provider = root.provider;
    try {
      final config = _readConfig(root);
      if (!config.isPresent) {
        return ProjectConfig.none(provider, config: config);
      }
      final baselineFile = childFile(root, baselineFileName);
      return ProjectConfig(
        config: config,
        index: TokenIndex.build(config, provider),
        provider: provider,
        baseline: baselineFile.exists
            ? Baseline.parse(baselineFile.readAsStringSync())
            : Baseline.empty,
      );
    } on Object catch (error) {
      return ProjectConfig.none(
        provider,
        config: DtlConfig.none(
          rootPath: root.path,
          issues: [
            ConfigIssue(
              ConfigIssueSeverity.error,
              'Could not read the design_token_lints configuration: $error',
            ),
          ],
        ),
      );
    }
  }

  DtlConfig _readConfig(Folder root) {
    final standalone = childFile(root, 'design_token_lints.yaml');
    if (standalone.exists) {
      final Object? yaml;
      try {
        yaml = loadYaml(standalone.readAsStringSync());
      } on YamlException catch (error) {
        return DtlConfig.none(
          rootPath: root.path,
          issues: [
            ConfigIssue(
              ConfigIssueSeverity.error,
              'design_token_lints.yaml is not valid YAML: ${error.message}',
            ),
          ],
        );
      }
      return DtlConfig.parse(
        yaml ?? const <String, Object?>{},
        rootPath: root.path,
        source: ConfigSource.standalone,
      );
    }
    final options = childFile(root, 'analysis_options.yaml');
    if (options.exists) {
      final Object? yaml;
      try {
        yaml = loadYaml(options.readAsStringSync());
      } on YamlException {
        return DtlConfig.none(rootPath: root.path);
      }
      if (yaml is Map && yaml['design_token_lints'] != null) {
        return DtlConfig.parse(
          yaml['design_token_lints'],
          rootPath: root.path,
          source: ConfigSource.analysisOptions,
        );
      }
    }
    return DtlConfig.none(rootPath: root.path);
  }

  static int _stamp(ResourceProvider provider, String path) {
    final file = provider.getFile(path);
    return file.exists ? file.modificationStamp : -1;
  }
}

final class _CacheEntry {
  _CacheEntry(this.project, this.stamps);

  final ProjectConfig project;
  final Map<String, int> stamps;

  bool isFresh(ResourceProvider provider) {
    for (final MapEntry(key: path, value: stamp) in stamps.entries) {
      if (ConfigLoader._stamp(provider, path) != stamp) return false;
    }
    return true;
  }
}
