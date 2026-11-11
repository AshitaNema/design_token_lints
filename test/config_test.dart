import 'package:design_token_lints/src/config/config.dart';
import 'package:design_token_lints/src/config/rule_id.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

DtlConfig parse(String yaml, {ConfigSource source = ConfigSource.standalone}) =>
    DtlConfig.parse(loadYaml(yaml), rootPath: '/pkg', source: source);

void main() {
  const full = '''
design_system:
  paths: [lib/design_system/**, lib/theme/**]
  packages: [acme_design_system]
tokens:
  color: { class: AppColors, file: lib/design_system/app_colors.dart }
  spacing: { class: AppSpacing, file: lib/design_system/app_spacing.dart }
  radius: { class: AppRadius, file: lib/design_system/app_radius.dart }
  typography: { class: AppTypography, file: lib/design_system/app_typography.dart }
  shadow: { class: AppShadows, file: package:acme/shadows.dart }
allow:
  color: [Colors.transparent, 0xFF000000, Colors.red.shade100]
  spacing: [0, 2, 0.5]
  radius: [999]
matching:
  spacing_tolerance: 1
  radius_tolerance: 2
  color_delta_e: 2.5
components:
  ElevatedButton: { replacement: AppButton, import: 'package:acme_ui/acme_ui.dart' }
  Text: { replacement: AppText }
exclude: ["**/*.g.dart", "test/**"]
rules:
  avoid_magic_spacing: { exclude: [lib/legacy/**] }
''';

  group('parse', () {
    test('reads every section', () {
      final config = parse(full);
      expect(config.issues, isEmpty);
      expect(config.isPresent, isTrue);
      expect(config.rootPath, '/pkg');
      expect(config.designSystemPaths, [
        'lib/design_system/**',
        'lib/theme/**',
      ]);
      expect(config.designSystemPackages, {'acme_design_system'});
      expect(config.tokens.keys, {
        DesignCategory.color,
        DesignCategory.spacing,
        DesignCategory.radius,
        DesignCategory.typography,
        DesignCategory.shadow,
      });
      expect(config.tokens[DesignCategory.shadow]!.className, 'AppShadows');
      expect(
        config.tokens[DesignCategory.shadow]!.file,
        'package:acme/shadows.dart',
      );
      expect(config.allowColorValues, {0xFF000000});
      expect(config.allowColorNames, {'transparent', 'red.100'});
      expect(config.allowSpacing, {0, 2, 0.5});
      expect(config.allowRadius, {999});
      expect(config.spacingTolerance, 1);
      expect(config.radiusTolerance, 2);
      expect(config.colorDeltaE, 2.5);
      expect(config.components['ElevatedButton']!.replacement, 'AppButton');
      expect(
        config.components['ElevatedButton']!.import,
        'package:acme_ui/acme_ui.dart',
      );
      expect(config.components['Text']!.import, isNull);
      expect(config.exclude, ['**/*.g.dart', 'test/**']);
      expect(config.ruleExcludes[RuleId.avoidMagicSpacing], ['lib/legacy/**']);
    });

    test('defaults', () {
      final config = parse('{}');
      expect(config.isPresent, isTrue);
      expect(config.tokens, isEmpty);
      expect(config.spacingTolerance, 0);
      expect(config.colorDeltaE, 0);
      expect(config.isCategoryConfigured(DesignCategory.color), isFalse);
    });

    test('records the source', () {
      expect(
        parse('{}', source: ConfigSource.analysisOptions).source,
        ConfigSource.analysisOptions,
      );
    });

    test('rejects a configuration that is not a mapping', () {
      for (final yaml in ['[1, 2]', 'text', '42']) {
        final config = parse(yaml);
        expect(config.isPresent, isFalse, reason: yaml);
        expect(config.hasErrors, isTrue, reason: yaml);
      }
    });

    test('warns about unknown keys', () {
      final config = parse('''
unknown: 1
design_system: { path: [a] }
allow: { colors: [Colors.red] }
''');
      final messages = config.issues.map((i) => i.message);
      expect(messages, contains(contains('unknown key "unknown"')));
      expect(messages, contains(contains('design_system: unknown key "path"')));
      expect(messages, contains(contains('allow: unknown key "colors"')));
      expect(config.hasErrors, isFalse);
    });

    test('rejects token entries without class and file', () {
      final config = parse('''
tokens:
  color: { class: AppColors }
  spacing: { class: AppSpacing, file: lib/s.dart }
''');
      expect(config.hasErrors, isTrue);
      expect(config.tokens.keys, {DesignCategory.spacing});
    });

    test('warns about unknown token categories', () {
      final config = parse('''
tokens:
  elevation: { class: AppElevation, file: lib/e.dart }
  component: { class: X, file: lib/x.dart }
''');
      expect(config.tokens, isEmpty);
      expect(config.issues.length, 2);
    });

    test('rejects a component without a replacement', () {
      final config = parse('''
components:
  Text: { import: 'package:x/x.dart' }
''');
      expect(config.components, isEmpty);
      expect(config.hasErrors, isTrue);
    });

    test('rejects negative tolerances', () {
      final config = parse('matching: { spacing_tolerance: -1 }');
      expect(config.spacingTolerance, 0);
      expect(config.hasErrors, isTrue);
    });

    test('warns about unknown rules and bad list items', () {
      final config = parse('''
rules:
  no_such_rule: { exclude: [a] }
exclude: [1, a/**]
allow: { spacing: [x, 4], color: [nope] }
''');
      expect(config.issues, hasLength(4));
      expect(config.exclude, ['a/**']);
      expect(config.allowSpacing, {4});
    });

    test('reports a wrong type for a section', () {
      final config = parse('tokens: [a]');
      expect(config.hasErrors, isTrue);
      expect(config.tokens, isEmpty);
    });
  });

  group('categories', () {
    test('component needs components', () {
      expect(
        parse(
          'components: { Text: { replacement: AppText } }',
        ).isCategoryConfigured(DesignCategory.component),
        isTrue,
      );
      expect(
        parse('{}').isCategoryConfigured(DesignCategory.component),
        isFalse,
      );
    });

    test('no configuration configures nothing', () {
      final config = DtlConfig.none();
      expect(config.isPresent, isFalse);
      expect(config.isCategoryConfigured(DesignCategory.color), isFalse);
    });

    test('lookups by key and code', () {
      expect(DesignCategory.fromKey('spacing'), DesignCategory.spacing);
      expect(DesignCategory.fromKey('colors'), isNull);
      expect(RuleId.fromCode('avoid_raw_color'), RuleId.avoidRawColor);
      expect(RuleId.fromCode('nope'), isNull);
      expect(RuleId.avoidRawShadow.category, DesignCategory.shadow);
    });
  });

  group('path matching', () {
    final config = parse(full);

    test('design system paths', () {
      expect(
        config.isDesignSystemPath('lib/design_system/app_colors.dart'),
        isTrue,
      );
      expect(config.isDesignSystemPath('lib/design_system/a/b/c.dart'), isTrue);
      expect(config.isDesignSystemPath('lib/theme/theme.dart'), isTrue);
      expect(config.isDesignSystemPath('lib/screens/home.dart'), isFalse);
    });

    test('global and rule exclusions', () {
      expect(config.isExcluded('lib/a.g.dart'), isTrue);
      expect(config.isExcluded('test/a_test.dart'), isTrue);
      expect(config.isExcluded('lib/legacy/a.dart'), isFalse);
      expect(
        config.isExcluded('lib/legacy/a.dart', RuleId.avoidMagicSpacing),
        isTrue,
      );
      expect(
        config.isExcluded('lib/legacy/a.dart', RuleId.avoidRawColor),
        isFalse,
      );
    });

    test('color allow-list', () {
      expect(config.isColorAllowed(colorValue: 0xFF000000), isTrue);
      expect(config.isColorAllowed(colorName: 'transparent'), isTrue);
      expect(config.isColorAllowed(colorName: 'red.100'), isTrue);
      expect(config.isColorAllowed(colorName: 'red.200'), isFalse);
      expect(config.isColorAllowed(colorValue: 0xFF000001), isFalse);
    });
  });
}
