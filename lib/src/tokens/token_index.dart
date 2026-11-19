import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:path/path.dart' as p;

import '../ast/call_view.dart';
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
    this.access,
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

  /// For a token that is a field of a `static const` instance, how code
  /// reads it, with `{name}` for the field (see [TokenSource.access]).
  final String? access;

  /// Whether the token is read through an instance rather than as a
  /// `static const`, so it is not a constant expression.
  bool get isInstanceField => access != null;

  /// Whether [reference] needs a `BuildContext` named `context` in scope.
  bool get needsContext =>
      access != null && RegExp(r'\bcontext\b').hasMatch(access!);

  /// The source reference, for example `AppColors.primary`, or the [access]
  /// template filled in, for example `context.palette.brand`. For a
  /// component this is just the class name.
  String get reference {
    if (access != null) return access!.replaceAll('{name}', name);
    return name.isEmpty ? className : '$className.$name';
  }

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
      final importUri =
          source.import ?? _importUri(provider, file, source.file);
      final instance = source.instance;
      final result = instance == null
          ? _readClass(category, source.className, declaration, unit, importUri)
          : _readInstance(
              category,
              source,
              instance,
              declaration,
              unit,
              importUri,
            );
      if (result == null) {
        issues.add(
          ConfigIssue(
            ConfigIssueSeverity.error,
            'tokens.${category.key}: "${source.className}.$instance" is not '
            'a static const instance created with a constructor of '
            '${source.className} in "${source.file}".',
          ),
        );
        continue;
      }
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

  /// Reads the tokens of a class whose tokens are the fields of the
  /// `static const` [instance]: `static const light = AppPalette(brand: …)`.
  ///
  /// Each argument of the constructor call is mapped to its field through
  /// the constructor's initializing formal (`this.brand`). Returns `null` if
  /// [instance] is not such a constant.
  static ({List<TokenEntry> entries, List<SkippedToken> skipped})?
  _readInstance(
    DesignCategory category,
    TokenSource source,
    String instance,
    ClassDeclaration declaration,
    CompilationUnit unit,
    String? importUri,
  ) {
    final className = source.className;
    VariableDeclaration? variable;
    final constants = <String, VariableDeclaration>{};
    for (final member in declaration.body.members) {
      if (member is FieldDeclaration &&
          member.isStatic &&
          member.fields.isConst) {
        for (final field in member.fields.variables) {
          constants[field.name.lexeme] = field;
          if (field.name.lexeme == instance) variable = field;
        }
      }
    }
    final call = CallView.of(variable?.initializer);
    if (call == null || call.typeName != className) return null;
    ConstructorDeclaration? constructor;
    for (final member in declaration.body.members) {
      if (member is ConstructorDeclaration &&
          member.name?.lexeme == call.constructorName) {
        constructor = member;
      }
    }
    if (constructor == null) return null;

    // Parameter name to field name, for initializing formals only.
    final fieldOf = <String, String>{};
    final positionalFields = <String?>[];
    for (final parameter in constructor.parameters.parameters) {
      final field = parameter is FieldFormalParameter
          ? parameter.name.lexeme
          : null;
      final name = parameter.name?.lexeme;
      if (parameter.isNamed) {
        if (name != null && field != null) fieldOf[name] = field;
      } else {
        positionalFields.add(field);
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
        return (constants[name] ?? topLevel[name])?.initializer;
      }
      if (prefix == className) return constants[name]?.initializer;
      return null;
    }

    final evaluator = StaticEvaluator(resolve: resolve);
    final entries = <TokenEntry>[];
    final skipped = <SkippedToken>[];
    void read(String? field, String label, Expression expression) {
      final reference = '$className.$instance.$label';
      if (field == null) {
        skipped.add(
          SkippedToken(
            category: category,
            reference: reference,
            reason: 'The argument does not initialize a field (this.$label).',
          ),
        );
        return;
      }
      final value = evaluator.evaluate(category, expression);
      if (value == null) {
        skipped.add(
          SkippedToken(
            category: category,
            reference: reference,
            reason: 'The value cannot be evaluated statically.',
          ),
        );
        return;
      }
      entries.add(
        TokenEntry(
          category: category,
          className: className,
          name: field,
          value: value,
          importUri: importUri,
          access: source.access,
        ),
      );
    }

    for (final MapEntry(key: name, value: expression) in call.named.entries) {
      read(fieldOf[name], name, expression);
    }
    for (var i = 0; i < call.positional.length; i++) {
      final field = i < positionalFields.length ? positionalFields[i] : null;
      read(field, field ?? '#$i', call.positional[i]);
    }
    return (entries: entries, skipped: skipped);
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
