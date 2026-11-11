import 'package:path/path.dart' as p;

/// Why a file is not checked.
enum Exemption {
  /// The file is under `design_system.paths`.
  designSystemPath,

  /// The file belongs to a package listed in `design_system.packages`.
  designSystemPackage,

  /// The file declares the tokens.
  tokenFile,

  /// The file is generated.
  generated,

  /// The file matches `exclude`.
  excluded,

  /// The file matches the `exclude` of the rule being run.
  ruleExcluded,
}

/// Recognizes generated Dart files by name and by header.
bool isGeneratedFile(String path, [String? content]) {
  const suffixes = [
    '.g.dart',
    '.freezed.dart',
    '.gr.dart',
    '.gen.dart',
    '.config.dart',
    '.mocks.dart',
    '.chopper.dart',
    '.pb.dart',
    '.pbenum.dart',
    '.pbjson.dart',
    '.pbgrpc.dart',
  ];
  if (suffixes.any(path.endsWith)) return true;
  if (content == null) return false;
  final header = content.length > 1024 ? content.substring(0, 1024) : content;
  return header.contains('GENERATED CODE') ||
      header.contains('@generated') ||
      header.contains('DO NOT EDIT');
}

/// Converts an absolute [path] into a `/`-separated path relative to [root].
String relativePosix(p.Context context, String root, String path) {
  final relative = context.relative(path, from: root);
  return p.posix.joinAll(context.split(relative));
}
