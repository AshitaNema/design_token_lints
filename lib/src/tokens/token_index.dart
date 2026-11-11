import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../config/package_locator.dart';
import '../config/rule_id.dart';
import 'static_evaluator.dart';
import 'token_value.dart';

/// One design token: a `static const` member of a configured token class.
final class TokenEntry {
  /// Creates a token entry.
  const TokenEntry({
    required this.category,
    required this.className,
    required this.name,
    required this.value,
    this.importUri,
  });

  /// The category the token belongs to.
  final DesignCategory category;

  /// The declaring class, for example `AppColors`.
  final String className;

  /// The member name, for example `primary`.
  final String name;

  /// The evaluated value.
  final TokenValue value;

  /// The library to import to use the token, if it can be determined.
  final String? importUri;

  /// The source reference, for example `AppColors.primary`. For a component
  /// this is just the class name.
  String get reference => name.isEmpty ? className : '$className.$name';

  @override
  String toString() => 'TokenEntry($reference = $value)';
}

/// A token member that could not be evaluated statically.
final class SkippedToken {
  /// Creates a skipped-token record.
  const SkippedToken({
    required this.category,
    required this.reference,
    required this.reason,
  });

  /// The category the token was declared for.
  final DesignCategory category;

  /// The source reference, for example `AppColors.dynamicTint`.
  final String reference;

  /// Why the member was skipped.
  final String reason;
}

/// The tokens of a project, discovered by parsing the configured token files.
///
/// Files are parsed without resolution, so no build step is needed.
final class TokenIndex {
  TokenIndex._({
    required this.entries,
    required this.skipped,
    required this.issues,
    required this.tokenFilePaths,
    required this.watchedPaths,
    required this.tokenClassNames,
  });

  /// An index with no tokens.
  static final TokenIndex empty = TokenIndex._(
    entries: const {},
    skipped: const [],
    issues: const [],
    tokenFilePaths: const {},
    watchedPaths: const {},
    tokenClassNames: const {},
  );

  /// Builds the index described by [config], reading files through [provider].
  static TokenIndex build(DtlConfig config, ResourceProvider provider) {
    final entries = <DesignCategory, List<TokenEntry>>{};
    final skipped = <SkippedToken>[];
    final issues = <ConfigIssue>[];
    final filePaths = <String>{};
    final watched = <String>{};
    final classNames = <DesignCategory, String>{};
    final root = provider.getFolder(config.rootPath);

    for (final MapEntry(key: category, value: source)
        in config.tokens.entries) {
      final file = _resolveFile(provider, root, source.file);
      if (file != null) watched.add(file.path);
      if (file == null || !file.exists) {
        issues.add(
          ConfigIssue(
            ConfigIssueSeverity.error,
            'tokens.${category.key}: file "${source.file}" was not found.',
          ),
        );
        continue;
      }
      filePaths.add(file.path);
      final ClassDeclaration? declaration;
      final CompilationUnit unit;
      try {
        unit = parseString(
          content: file.readAsStringSync(),
          path: file.path,
          throwIfDiagnostics: false,
        ).unit;
      } on Object catch (error) {
        issues.add(
          ConfigIssue(
            ConfigIssueSeverity.error,
            'tokens.${category.key}: could not read "${source.file}": $error',
          ),
        );
        continue;
      }
      declaration = _findClass(unit, source.className);
      if (declaration == null) {
        issues.add(
          ConfigIssue(
            ConfigIssueSeverity.error,
            'tokens.${category.key}: class "${source.className}" was not '
            'found in "${source.file}".',
          ),
        );
        continue;
      }
      classNames[category] = source.className;
      final importUri = _importUri(provider, file, source.file);
      final result = _readClass(
        category,
        source.className,
        declaration,
        unit,
        importUri,
      );
      entries[category] = result.entries;
      skipped.addAll(result.skipped);
    }

    return TokenIndex._(
      entries: entries,
      skipped: skipped,
      issues: issues,
      tokenFilePaths: filePaths,
      watchedPaths: watched,
      tokenClassNames: Set.of(classNames.values),
    );
  }

  /// The discovered tokens by category.
  final Map<DesignCategory, List<TokenEntry>> entries;

  /// Members that could not be evaluated.
  final List<SkippedToken> skipped;

  /// Problems finding or reading token files.
  final List<ConfigIssue> issues;

  /// Absolute paths of the token files.
  final Set<String> tokenFilePaths;

  /// Every token file path that was looked up, including missing ones; used
  /// to invalidate caches.
  final Set<String> watchedPaths;

  /// Names of the token classes that were found.
  final Set<String> tokenClassNames;

  /// The tokens of [category]; empty if none.
  List<TokenEntry> of(DesignCategory category) => entries[category] ?? const [];

  /// Whether the token class for [category] was found and read.
  bool hasCategory(DesignCategory category) => entries.containsKey(category);

  /// The total number of tokens.
  int get length => entries.values.fold(0, (sum, list) => sum + list.length);

  /// The category whose token class is called [className], if any.
  DesignCategory? categoryOfClass(String className) {
    for (final MapEntry(key: category, value: list) in entries.entries) {
      if (list.any((e) => e.className == className)) return category;
    }
    return null;
  }

  static File? _resolveFile(
    ResourceProvider provider,
    Folder root,
    String reference,
  ) {
    if (reference.startsWith('package:')) {
      return PackageLocator.resolvePackageUri(provider, root, reference);
    }
    final context = provider.pathContext;
    final path = context.isAbsolute(reference)
        ? reference
        : context.normalize(context.join(root.path, reference));
    return provider.getFile(path);
  }

  static String? _importUri(
    ResourceProvider provider,
    File file,
    String reference,
  ) {
    if (reference.startsWith('package:')) return reference;
    final package = PackageLocator.nearest(file);
    if (package == null || package.name.isEmpty) return null;
    final context = provider.pathContext;
    final lib = context.join(package.root.path, 'lib');
    if (!context.isWithin(lib, file.path)) return null;
    final relative = p.posix.joinAll(
      context.split(context.relative(file.path, from: lib)),
    );
    return 'package:${package.name}/$relative';
  }

  static ClassDeclaration? _findClass(CompilationUnit unit, String name) {
    for (final declaration in unit.declarations) {
      if (declaration is ClassDeclaration &&
          declaration.namePart.typeName.lexeme == name) {
        return declaration;
      }
    }
    return null;
  }

  static ({List<TokenEntry> entries, List<SkippedToken> skipped}) _readClass(
    DesignCategory category,
    String className,
    ClassDeclaration declaration,
    CompilationUnit unit,
    String? importUri,
  ) {
    final fields = <String, VariableDeclaration>{};
    for (final member in declaration.body.members) {
      if (member is FieldDeclaration &&
          member.isStatic &&
          member.fields.isConst) {
        for (final variable in member.fields.variables) {
          fields[variable.name.lexeme] = variable;
        }
      }
    }
    final topLevel = <String, VariableDeclaration>{};
    for (final member in unit.declarations) {
      if (member is TopLevelVariableDeclaration && member.variables.isConst) {
        for (final variable in member.variables.variables) {
          topLevel[variable.name.lexeme] = variable;
        }
      }
    }

    Expression? resolve(String? prefix, String name) {
      if (prefix == null) {
        return (fields[name] ?? topLevel[name])?.initializer;
      }
      if (prefix == className) return fields[name]?.initializer;
      return null;
    }

    final evaluator = StaticEvaluator(resolve: resolve);
    final entries = <TokenEntry>[];
    final skipped = <SkippedToken>[];
    for (final MapEntry(key: name, value: variable) in fields.entries) {
      final initializer = variable.initializer;
      if (initializer == null) continue;
      final value = evaluator.evaluate(category, initializer);
      if (value == null) {
        skipped.add(
          SkippedToken(
            category: category,
            reference: '$className.$name',
            reason: 'The value cannot be evaluated statically.',
          ),
        );
        continue;
      }
      entries.add(
        TokenEntry(
          category: category,
          className: className,
          name: name,
          value: value,
          importUri: importUri,
        ),
      );
    }
    return (entries: entries, skipped: skipped);
  }
}
