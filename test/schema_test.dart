import 'dart:convert';
import 'dart:io';

import 'package:design_token_lints/src/config/config.dart';
import 'package:design_token_lints/src/config/rule_id.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// The schema must describe exactly the keys the configuration parser reads.
void main() {
  final schema =
      jsonDecode(File('doc/design_token_lints.schema.json').readAsStringSync())
          as Map<String, Object?>;

  Map<String, Object?> object(Map<String, Object?> node, String key) =>
      node[key]! as Map<String, Object?>;

  Set<String> keysOf(Map<String, Object?> node) =>
      object(node, 'properties').keys.toSet();

  Map<String, Object?> section(String key) =>
      object(object(schema, 'properties'), key);

  Map<String, Object?> definition(String key) =>
      object(object(schema, 'definitions'), key);

  test('is draft-07 and points at its published location', () {
    expect(schema[r'$schema'], 'http://json-schema.org/draft-07/schema#');
    expect(
      schema[r'$id'],
      'https://raw.githubusercontent.com/AshitaNema/design_token_lints/main/'
      'doc/design_token_lints.schema.json',
    );
  });

  test('top-level keys', () {
    expect(keysOf(schema), ConfigKeys.topLevel);
  });

  test('section keys', () {
    expect(keysOf(section('design_system')), ConfigKeys.designSystem);
    expect(keysOf(section('allow')), ConfigKeys.allow);
    expect(keysOf(section('matching')), ConfigKeys.matching);
    expect(keysOf(definition('tokenSource')), ConfigKeys.tokenSource);
    expect(keysOf(definition('component')), ConfigKeys.component);
    expect(keysOf(definition('ruleOptions')), ConfigKeys.rule);
    expect(keysOf(section('design_tokens')), ConfigKeys.designTokens);
    expect(keysOf(definition('designTokenGroup')), ConfigKeys.designTokenGroup);
    expect(
      keysOf(
        object(section('design_tokens'), 'properties')['map']!
            as Map<String, Object?>,
      ),
      {
        for (final category in DesignCategory.values)
          if (category.isToken) category.key,
      },
    );
  });

  test('token categories and rules', () {
    expect(keysOf(section('tokens')), {
      for (final category in DesignCategory.values)
        if (category.isToken) category.key,
    });
    expect(keysOf(section('rules')), {
      for (final rule in RuleId.values) rule.code,
    });
  });

  test('every section rejects unknown keys, as the parser warns', () {
    for (final node in [
      schema,
      section('design_system'),
      section('tokens'),
      section('allow'),
      section('matching'),
      section('rules'),
      section('design_tokens'),
      definition('designTokenGroup'),
      definition('tokenSource'),
      definition('component'),
      definition('ruleOptions'),
    ]) {
      expect(node['additionalProperties'], isFalse);
    }
  });

  test('the configurations in this repository parse without issues', () {
    for (final path in [
      'example/design_token_lints.yaml',
      'test/fixtures/acme/design_token_lints.yaml',
    ]) {
      final config = DtlConfig.parse(
        loadYaml(File(path).readAsStringSync()),
        rootPath: '/',
        source: ConfigSource.standalone,
      );
      expect(config.issues, isEmpty, reason: path);
    }
  });
}
