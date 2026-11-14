import 'dart:convert';

import 'package:yaml/yaml.dart';

import '../detectors/finding.dart';
import 'config.dart';
import 'rule_id.dart';

/// The name of the baseline file, stored next to the configuration.
const baselineFileName = 'design_token_lints.baseline.yaml';

/// Findings a project has accepted, so that only new ones are reported.
///
/// A finding is identified by its file, its rule and its source code as the
/// analyzer prints it, so moving or reformatting code keeps it baselined. The
/// baseline stores how many findings with the same identity a file may have;
/// further ones, in source order, are reported.
final class Baseline {
  Baseline._(this._files, this.issues);

  /// Builds a baseline from findings, keyed by file paths relative to the
  /// configuration directory with `/` separators.
  factory Baseline.of(Map<String, List<Finding>> findingsByFile) {
    final files = <String, Map<RuleId, Map<String, int>>>{};
    for (final MapEntry(key: path, value: findings) in findingsByFile.entries) {
      for (final finding in findings) {
        final keys = files
            .putIfAbsent(path, () => {})
            .putIfAbsent(finding.rule, () => {});
        final key = keyOf(finding);
        keys[key] = (keys[key] ?? 0) + 1;
      }
    }
    return Baseline._(files, const []);
  }

  /// Parses the content of a baseline file.
  ///
  /// Parsing never throws: problems become [issues], and the parts that
  /// cannot be read accept nothing.
  factory Baseline.parse(String content) {
    final Object? yaml;
    try {
      yaml = loadYaml(content);
    } on YamlException catch (error) {
      return Baseline._(const {}, [
        _issue('$baselineFileName is not valid YAML: ${error.message}'),
      ]);
    }
    if (yaml == null) return Baseline._(const {}, const []);
    if (yaml is! Map) {
      return Baseline._(const {}, [
        _issue('$baselineFileName must be a mapping.'),
      ]);
    }
    final version = yaml['version'];
    if (version != 1) {
      return Baseline._(const {}, [
        _issue(
          '$baselineFileName has version $version; this version of '
          'design_token_lints reads version 1. Run '
          '"design_token_lints baseline" to rewrite it.',
        ),
      ]);
    }
    final issues = <ConfigIssue>[];
    final files = <String, Map<RuleId, Map<String, int>>>{};
    final filesNode = yaml['files'];
    if (filesNode is Map) {
      for (final MapEntry(key: path, value: rules) in filesNode.entries) {
        if (path is! String || rules is! Map) continue;
        for (final MapEntry(key: ruleName, value: keys) in rules.entries) {
          final rule = RuleId.values.where((r) => r.code == ruleName);
          if (rule.isEmpty) {
            issues.add(
              _issue('$baselineFileName names an unknown rule "$ruleName".'),
            );
            continue;
          }
          if (keys is! Map) continue;
          for (final MapEntry(key: key, value: count) in keys.entries) {
            if (key is! String || count is! int || count < 1) continue;
            files
                    .putIfAbsent(path, () => {})
                    .putIfAbsent(rule.single, () => {})[key] =
                count;
          }
        }
      }
    } else if (filesNode != null) {
      issues.add(_issue('"files" in $baselineFileName must be a mapping.'));
    }
    return Baseline._(files, issues);
  }

  /// A baseline that accepts nothing.
  static final Baseline empty = Baseline._(const {}, const []);

  static ConfigIssue _issue(String message) =>
      ConfigIssue(ConfigIssueSeverity.warning, message);

  final Map<String, Map<RuleId, Map<String, int>>> _files;

  /// Problems found while parsing.
  final List<ConfigIssue> issues;

  /// Whether the baseline accepts nothing.
  bool get isEmpty => _files.isEmpty;

  /// The number of accepted findings.
  int get total => _files.values.fold(
    0,
    (sum, rules) =>
        sum +
        rules.values.fold(
          0,
          (sum, keys) => sum + keys.values.fold(0, (sum, n) => sum + n),
        ),
  );

  /// The files with accepted findings, relative to the configuration.
  Iterable<String> get paths => _files.keys;

  /// The identity of [finding] within its file and rule.
  static String keyOf(Finding finding) =>
      finding.node.toSource().replaceAll(RegExp(r'\s+'), ' ');

  /// Starts matching the findings of the file at [relativePath].
  ///
  /// Pass the file's findings to [BaselineMatcher.accepts] in source order.
  BaselineMatcher matcherFor(String relativePath) =>
      BaselineMatcher._(_files[relativePath] ?? const {});

  /// This baseline with the files that [keep] rejects replaced by [other]'s.
  ///
  /// Used to rewrite part of a project: [keep] says which existing entries
  /// lie outside the part that was analyzed again.
  Baseline mergedWith(Baseline other, bool Function(String path) keep) =>
      Baseline._({
        for (final MapEntry(key: path, value: rules) in _files.entries)
          if (keep(path)) path: rules,
        ...other._files,
      }, const []);

  /// The baseline as the content of a baseline file.
  String serialize() {
    final out = StringBuffer()
      ..writeln('# Findings accepted with "design_token_lints baseline". They')
      ..writeln('# are not reported; new ones are. Run the command again after')
      ..writeln('# fixing some to shrink this file.')
      ..writeln('version: 1');
    if (_files.isEmpty) {
      out.writeln('files: {}');
      return out.toString();
    }
    out.writeln('files:');
    for (final path in _files.keys.toList()..sort()) {
      out.writeln('  ${jsonEncode(path)}:');
      final rules = _files[path]!;
      for (final rule in RuleId.values) {
        final keys = rules[rule];
        if (keys == null || keys.isEmpty) continue;
        out.writeln('    ${rule.code}:');
        for (final key in keys.keys.toList()..sort()) {
          out.writeln('      ${jsonEncode(key)}: ${keys[key]}');
        }
      }
    }
    return out.toString();
  }
}

/// Matches the findings of one file against a [Baseline].
final class BaselineMatcher {
  BaselineMatcher._(this._allowed);

  final Map<RuleId, Map<String, int>> _allowed;
  final Map<(RuleId, String), int> _seen = {};

  /// Whether [finding] is accepted by the baseline.
  ///
  /// Findings must be passed in source order: when a file has more findings
  /// with the same identity than the baseline accepts, the later ones are
  /// reported.
  bool accepts(Finding finding) {
    final allowed = _allowed[finding.rule];
    if (allowed == null) return false;
    final key = Baseline.keyOf(finding);
    final limit = allowed[key];
    if (limit == null) return false;
    final seen = (_seen[(finding.rule, key)] ?? 0) + 1;
    _seen[(finding.rule, key)] = seen;
    return seen <= limit;
  }
}
