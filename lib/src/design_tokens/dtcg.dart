import 'dart:convert';

/// A token read from a Design Tokens Format Module (2025.10) file.
final class DesignToken {
  /// Creates a token.
  const DesignToken({
    required this.path,
    required this.type,
    required this.value,
  });

  /// The names from the root group to the token, for example
  /// `['color', 'brand', 'primary']`.
  final List<String> path;

  /// The token's `$type`, its group's, or its reference's; `null` if none
  /// applies.
  final String? type;

  /// The resolved `$value`: references are replaced by the values they point
  /// to, also inside composite values.
  final Object? value;

  /// The path joined with dots, as in a `{group.token}` reference.
  String get name => path.join('.');
}

/// A token or group the file describes that cannot be used.
final class DesignTokenProblem {
  /// Creates a problem.
  const DesignTokenProblem(this.path, this.message);

  /// The dotted path of the token or group, or `''` for the whole file.
  final String path;

  /// What is wrong.
  final String message;

  @override
  String toString() => path.isEmpty ? message : '$path: $message';
}

/// The tokens of a design tokens file.
final class DesignTokenFile {
  DesignTokenFile._(this.tokens, this.problems);

  /// Parses [content], a design tokens file in the JSON format of the Design
  /// Tokens Format Module 2025.10.
  ///
  /// Parsing never throws. Groups and tokens are read with `$type`
  /// inheritance; `{group.token}` aliases and JSON Pointer `$ref`s are
  /// resolved, also in chains, and cycles are reported. `$extends` is not
  /// supported and is reported.
  factory DesignTokenFile.parse(String content) {
    final Object? json;
    try {
      json = jsonDecode(content);
    } on FormatException catch (error) {
      return DesignTokenFile._(const [], [
        DesignTokenProblem('', 'not valid JSON: ${error.message}'),
      ]);
    }
    if (json is! Map<String, Object?>) {
      return DesignTokenFile._(const [], [
        const DesignTokenProblem('', 'the file must be a JSON object'),
      ]);
    }
    return _Parser(json).run();
  }

  /// The tokens, in file order.
  final List<DesignToken> tokens;

  /// Tokens and groups that could not be read.
  final List<DesignTokenProblem> problems;

  /// The tokens under the group at [groupPath] (dotted, `''` for the root),
  /// keyed by their path relative to that group.
  Map<String, DesignToken> under(String groupPath) {
    final prefix = groupPath.isEmpty ? <String>[] : groupPath.split('.');
    return {
      for (final token in tokens)
        if (token.path.length > prefix.length &&
            _startsWith(token.path, prefix))
          token.path.sublist(prefix.length).join('.'): token,
    };
  }

  static bool _startsWith(List<String> path, List<String> prefix) {
    for (var i = 0; i < prefix.length; i++) {
      if (path[i] != prefix[i]) return false;
    }
    return true;
  }
}

final class _Unresolved implements Exception {
  const _Unresolved(this.message);
  final String message;
}

final class _Parser {
  _Parser(this.root);

  final Map<String, Object?> root;

  /// Raw tokens by dotted path, with their declared or inherited type.
  final Map<String, ({List<String> path, String? type, Object? raw})> _raw = {};
  final List<DesignTokenProblem> _problems = [];

  DesignTokenFile run() {
    _walk(root, const [], null);
    final tokens = <DesignToken>[];
    for (final MapEntry(key: name, value: token) in _raw.entries) {
      try {
        final value = _resolve(token.raw, {name});
        final type = token.type ?? _referencedType(token.raw, {name});
        tokens.add(DesignToken(path: token.path, type: type, value: value));
      } on _Unresolved catch (error) {
        _problems.add(DesignTokenProblem(name, error.message));
      }
    }
    return DesignTokenFile._(tokens, _problems);
  }

  void _walk(Map<String, Object?> group, List<String> path, String? type) {
    if (group.containsKey(r'$extends')) {
      _problems.add(
        DesignTokenProblem(
          path.join('.'),
          r'$extends is not supported; the group is read without it',
        ),
      );
    }
    final groupType = group[r'$type'];
    final inherited = groupType is String ? groupType : type;
    for (final MapEntry(key: key, value: child) in group.entries) {
      if (key.startsWith(r'$') && key != r'$root') continue;
      if (child is! Map<String, Object?>) continue;
      final childPath = [...path, if (key != r'$root') key];
      final isToken =
          child.containsKey(r'$value') ||
          (child.containsKey(r'$ref') && !_hasChildren(child));
      if (isToken) {
        final ownType = child[r'$type'];
        _raw[childPath.join('.')] = (
          path: childPath,
          type: ownType is String ? ownType : inherited,
          raw: child.containsKey(r'$value') ? child[r'$value'] : child,
        );
      } else {
        _walk(child, childPath, inherited);
      }
    }
  }

  static bool _hasChildren(Map<String, Object?> node) =>
      node.keys.any((key) => !key.startsWith(r'$'));

  static final _alias = RegExp(r'^\{([^{}]+)\}$');

  /// Resolves aliases and `$ref`s in [value]; [visiting] holds the tokens on
  /// the current chain, to detect cycles.
  Object? _resolve(Object? value, Set<String> visiting) {
    if (value is String) {
      final alias = _alias.firstMatch(value);
      if (alias == null) return value;
      final target = alias.group(1)!;
      final token = _raw[target];
      if (token == null) {
        throw _Unresolved('the reference {$target} does not name a token');
      }
      if (!visiting.add(target)) {
        throw _Unresolved('circular reference through {$target}');
      }
      final resolved = _resolve(token.raw, visiting);
      visiting.remove(target);
      return resolved;
    }
    if (value is Map<String, Object?>) {
      final ref = value[r'$ref'];
      if (ref is String) return _resolve(_pointer(ref, visiting), visiting);
      return {
        for (final MapEntry(:key, :value) in value.entries)
          key: _resolve(value, visiting),
      };
    }
    if (value is List<Object?>) {
      return [for (final item in value) _resolve(item, visiting)];
    }
    return value;
  }

  /// The node at the JSON Pointer [pointer] (RFC 6901), within this file.
  Object? _pointer(String pointer, Set<String> visiting) {
    if (!pointer.startsWith('#')) {
      throw _Unresolved(r'only $ref pointers within the file are supported');
    }
    if (!visiting.add('\$ref:$pointer')) {
      throw _Unresolved('circular reference through $pointer');
    }
    Object? node = root;
    final segments = pointer.length <= 2
        ? const <String>[]
        : pointer.substring(2).split('/');
    for (final raw in segments) {
      final segment = raw.replaceAll('~1', '/').replaceAll('~0', '~');
      final index = int.tryParse(segment);
      if (node is Map<String, Object?> && node.containsKey(segment)) {
        node = node[segment];
      } else if (node is List<Object?> &&
          index != null &&
          index >= 0 &&
          index < node.length) {
        node = node[index];
      } else {
        throw _Unresolved('the reference $pointer points nowhere');
      }
    }
    return node;
  }

  /// The type of the token a whole-value alias points to, following chains.
  String? _referencedType(Object? raw, Set<String> visiting) {
    if (raw is! String) return null;
    final alias = _alias.firstMatch(raw);
    if (alias == null) return null;
    final target = alias.group(1)!;
    final token = _raw[target];
    if (token == null || !visiting.add(target)) return null;
    return token.type ?? _referencedType(token.raw, visiting);
  }
}
