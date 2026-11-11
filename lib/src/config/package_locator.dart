import 'dart:convert';

import 'package:analyzer/file_system/file_system.dart';
import 'package:yaml/yaml.dart';

/// Returns the file called [name] inside [folder].
///
/// Goes through [ResourceProvider.getFile] because `Folder.getFile` is not
/// available in every supported analyzer version.
File childFile(Folder folder, String name) => folder.provider.getFile(
  folder.provider.pathContext.join(folder.path, name),
);

/// Returns the folder called [name] inside [folder].
Folder childFolder(Folder folder, String name) => folder.provider.getFolder(
  folder.provider.pathContext.join(folder.path, name),
);

/// A Dart package found on disk.
final class PackageInfo {
  /// Creates package information.
  const PackageInfo({
    required this.root,
    required this.name,
    required this.isWorkspaceMember,
    required this.isWorkspaceRoot,
  });

  /// The directory that contains `pubspec.yaml`.
  final Folder root;

  /// The package name.
  final String name;

  /// Whether the pubspec has `resolution: workspace`.
  final bool isWorkspaceMember;

  /// Whether the pubspec declares a `workspace:` list.
  final bool isWorkspaceRoot;
}

/// Finds packages by walking up the directory tree.
final class PackageLocator {
  const PackageLocator._();

  /// Returns the package that contains [resource], or `null`.
  static PackageInfo? nearest(Resource resource) {
    Folder? folder = resource is Folder ? resource : resource.parent;
    while (true) {
      final info = read(folder!);
      if (info != null) return info;
      if (folder.isRoot) return null;
      folder = folder.parent;
    }
  }

  static final Expando<Map<String, _CachedPackage>> _cache = Expando();

  /// Reads the pubspec in [folder], or returns `null` if it has none.
  ///
  /// Results are cached until the pubspec changes.
  static PackageInfo? read(Folder folder) {
    final pubspec = childFile(folder, 'pubspec.yaml');
    final entries = _cache[folder.provider] ??= {};
    if (!pubspec.exists) {
      entries.remove(pubspec.path);
      return null;
    }
    final stamp = pubspec.modificationStamp;
    final cached = entries[pubspec.path];
    if (cached != null && cached.stamp == stamp) return cached.info;
    final info = _parse(folder, pubspec);
    entries[pubspec.path] = _CachedPackage(stamp, info);
    return info;
  }

  static PackageInfo? _parse(Folder folder, File pubspec) {
    try {
      final yaml = loadYaml(pubspec.readAsStringSync());
      if (yaml is! Map) return null;
      return PackageInfo(
        root: folder,
        name: yaml['name'] is String ? yaml['name'] as String : '',
        isWorkspaceMember: yaml['resolution'] == 'workspace',
        isWorkspaceRoot: yaml['workspace'] != null,
      );
    } on Object {
      return null;
    }
  }

  /// Returns the workspace root above [member], or `null`.
  static PackageInfo? workspaceRootOf(PackageInfo member) {
    if (!member.isWorkspaceMember) return null;
    var folder = member.root;
    while (!folder.isRoot) {
      folder = folder.parent;
      final info = read(folder);
      if (info != null && info.isWorkspaceRoot) return info;
    }
    return null;
  }

  /// Resolves a `package:` URI through the nearest `package_config.json` at or
  /// above [from], or returns `null`.
  static File? resolvePackageUri(
    ResourceProvider provider,
    Folder from,
    String uri,
  ) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null || parsed.scheme != 'package') return null;
    final segments = parsed.pathSegments;
    if (segments.length < 2) return null;
    final packageName = segments.first;
    final rest = segments.skip(1).join('/');

    var folder = from;
    while (true) {
      final config = childFile(
        childFolder(folder, '.dart_tool'),
        'package_config.json',
      );
      if (config.exists) {
        return _lookup(provider, config, packageName, rest);
      }
      if (folder.isRoot) return null;
      folder = folder.parent;
    }
  }

  static File? _lookup(
    ResourceProvider provider,
    File config,
    String packageName,
    String rest,
  ) {
    try {
      final json = jsonDecode(config.readAsStringSync());
      if (json is! Map || json['packages'] is! List) return null;
      for (final entry in json['packages'] as List<Object?>) {
        if (entry is! Map || entry['name'] != packageName) continue;
        final configDir = config.parent;
        var rootUri = Uri.parse('${entry['rootUri']}');
        if (!rootUri.path.endsWith('/')) {
          rootUri = rootUri.replace(path: '${rootUri.path}/');
        }
        final base = provider.pathContext.toUri('${configDir.path}/');
        final root = base.resolveUri(rootUri);
        var packageUri = Uri.parse('${entry['packageUri'] ?? 'lib/'}');
        if (!packageUri.path.endsWith('/')) {
          packageUri = packageUri.replace(path: '${packageUri.path}/');
        }
        final lib = root.resolveUri(packageUri);
        final fileUri = lib.resolve(rest);
        return provider.getFile(provider.pathContext.fromUri(fileUri));
      }
    } on Object {
      return null;
    }
    return null;
  }
}

final class _CachedPackage {
  const _CachedPackage(this.stamp, this.info);

  final int stamp;
  final PackageInfo? info;
}
