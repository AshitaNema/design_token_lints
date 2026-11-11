import 'package:analyzer/file_system/memory_file_system.dart';
import 'package:design_token_lints/src/config/config.dart';
import 'package:design_token_lints/src/config/config_loader.dart';
import 'package:design_token_lints/src/config/rule_id.dart';
import 'package:design_token_lints/src/tokens/token_index.dart';
import 'package:design_token_lints/src/tokens/token_value.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'support/rule_test_base.dart';

void main() {
  late MemoryResourceProvider provider;

  setUp(() {
    provider = MemoryResourceProvider();
    provider.newFile('/pkg/pubspec.yaml', 'name: acme\n');
  });

  TokenIndex build(String yaml) {
    final config = DtlConfig.parse(
      loadYaml(yaml),
      rootPath: '/pkg',
      source: ConfigSource.standalone,
    );
    return TokenIndex.build(config, provider);
  }

  void write(String name, String source) =>
      provider.newFile('/pkg/lib/$name.dart', source);

  TokenEntry entry(TokenIndex index, DesignCategory category, String name) =>
      index.of(category).singleWhere((e) => e.name == name);

  group('colors', () {
    test('extracts every supported form', () {
      write('c', '''
import 'package:flutter/material.dart';
abstract final class AppColors {
  static const hex = Color(0xFF1E88E5);
  static const argb = Color.fromARGB(255, 30, 136, 229);
  static const rgbo = Color.fromRGBO(30, 136, 229, 0.5);
  static const from = Color.from(alpha: 1, red: 1, green: 0, blue: 0);
  static const palette = Colors.red;
  static const shade = Colors.red.shade100;
  static const alias = hex;
  static const qualified = AppColors.hex;
  static const withConst = const Color(0xFF000001);
  static const untyped = Color(0x80FFFFFF);
}
''');
      final index = build('''
tokens:
  color: { class: AppColors, file: lib/c.dart }
''');
      expect(index.issues, isEmpty);
      expect(index.skipped, isEmpty);
      int argb(String name) =>
          (entry(index, DesignCategory.color, name).value as ColorValue).argb;
      expect(argb('hex'), 0xFF1E88E5);
      expect(argb('argb'), 0xFF1E88E5);
      expect(argb('rgbo'), 0x801E88E5);
      expect(argb('from'), 0xFFFF0000);
      expect(argb('palette'), 0xFFF44336);
      expect(argb('shade'), 0xFFFFCDD2);
      expect(argb('alias'), 0xFF1E88E5);
      expect(argb('qualified'), 0xFF1E88E5);
      expect(argb('withConst'), 0xFF000001);
      expect(argb('untyped'), 0x80FFFFFF);
    });

    test('skips what it cannot evaluate and says why', () {
      write('c', '''
import 'package:flutter/material.dart';
abstract final class AppColors {
  static const ok = Color(0xFF000000);
  static Color computed(int v) => Color(v);
  static const dynamicTint = Color.lerp(Colors.red, Colors.blue, 0.5);
  static const cyc1 = cyc2;
  static const cyc2 = cyc1;
  static final notConst = Color(0xFF111111);
  static const Color unknown = somethingElse;
}
''');
      final index = build('''
tokens:
  color: { class: AppColors, file: lib/c.dart }
''');
      expect(index.of(DesignCategory.color).map((e) => e.name), ['ok']);
      expect(index.skipped.map((s) => s.reference), [
        'AppColors.dynamicTint',
        'AppColors.cyc1',
        'AppColors.cyc2',
        'AppColors.unknown',
      ]);
      expect(index.skipped.first.reason, isNotEmpty);
    });
  });

  group('numbers', () {
    test('extracts literals, arithmetic and references', () {
      write('s', '''
const _base = 4;
abstract final class AppSpacing {
  static const double xs = 4;
  static const sm = 8.0;
  static const md = xs * 4;
  static const lg = AppSpacing.md + sm;
  static const fromTopLevel = _base * 3;
  static const negative = -2;
  static const halved = 10 / 4;
  static const parenthesised = (1 + 2) * 2;
  static const String label = 'x';
  static var notConst = 1;
  static const divideByZero = 1 / 0;
}
''');
      final index = build('''
tokens:
  spacing: { class: AppSpacing, file: lib/s.dart }
''');
      double value(String name) =>
          (entry(index, DesignCategory.spacing, name).value as NumberValue)
              .value;
      expect(value('xs'), 4);
      expect(value('sm'), 8);
      expect(value('md'), 16);
      expect(value('lg'), 24);
      expect(value('fromTopLevel'), 12);
      expect(value('negative'), -2);
      expect(value('halved'), 2.5);
      expect(value('parenthesised'), 6);
      expect(index.skipped.map((s) => s.reference), [
        'AppSpacing.label',
        'AppSpacing.divideByZero',
      ]);
    });
  });

  group('radius', () {
    test('extracts doubles, Radius and BorderRadius', () {
      write('r', '''
abstract final class AppRadius {
  static const sm = 4.0;
  static const md = Radius.circular(8);
  static const lg = BorderRadius.circular(16);
  static const xl = BorderRadius.all(Radius.circular(24));
  static const alias = md;
  static const only = BorderRadius.only(topLeft: Radius.circular(4));
}
''');
      final index = build('''
tokens:
  radius: { class: AppRadius, file: lib/r.dart }
''');
      TokenValue value(String name) =>
          entry(index, DesignCategory.radius, name).value;
      expect(value('sm'), const NumberValue(4));
      expect(value('md'), const RadiusValue(8));
      expect(value('lg'), const BorderRadiusValue(16));
      expect(value('xl'), const BorderRadiusValue(24));
      expect(value('alias'), const RadiusValue(8));
      expect(index.skipped.map((s) => s.reference), ['AppRadius.only']);
    });
  });

  group('typography', () {
    test('extracts the identifying properties', () {
      write('t', '''
abstract final class AppTypography {
  static const body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.4,
    letterSpacing: 0.25,
    color: Colors.black,
    fontFamily: 'Inter',
  );
  static const bold = TextStyle(fontWeight: FontWeight.bold);
  static const normal = TextStyle(fontWeight: FontWeight.normal, fontSize: 1);
  static const heavy = TextStyle(fontWeight: FontWeight.w900, fontSize: 1);
  static const alias = body;
  static const unevaluable = TextStyle(fontSize: size);
  static const wrong = Color(0xFF000000);
}
''');
      final index = build('''
tokens:
  typography: { class: AppTypography, file: lib/t.dart }
''');
      TokenValue value(String name) =>
          entry(index, DesignCategory.typography, name).value;
      expect(
        value('body'),
        const TextStyleValue(
          fontSize: 14,
          fontWeight: 400,
          height: 1.4,
          letterSpacing: 0.25,
        ),
      );
      expect(value('bold'), const TextStyleValue(fontWeight: 700));
      expect(
        value('normal'),
        const TextStyleValue(fontSize: 1, fontWeight: 400),
      );
      expect(
        value('heavy'),
        const TextStyleValue(fontSize: 1, fontWeight: 900),
      );
      expect(value('alias'), value('body'));
      expect(index.skipped.map((s) => s.reference), [
        'AppTypography.unevaluable',
        'AppTypography.wrong',
      ]);
    });
  });

  group('shadows', () {
    test('extracts single shadows and lists', () {
      write('sh', '''
abstract final class AppShadows {
  static const one = BoxShadow(
    color: Color(0x1A000000),
    blurRadius: 8,
    spreadRadius: 1,
    offset: Offset(0, 2),
  );
  static const list = [one, BoxShadow(blurRadius: 3)];
  static const plain = [BoxShadow(blurRadius: 3, color: Color(0xFF000000))];
  static const bad = [BoxShadow(blurRadius: blur)];
}
''');
      final index = build('''
tokens:
  shadow: { class: AppShadows, file: lib/sh.dart }
''');
      ShadowValue value(String name) =>
          entry(index, DesignCategory.shadow, name).value as ShadowValue;
      expect(value('one').isList, isFalse);
      expect(
        value('one').layers.single,
        const ShadowLayer(
          color: 0x1A000000,
          blurRadius: 8,
          spreadRadius: 1,
          dy: 2,
        ),
      );
      expect(value('plain').isList, isTrue);
      expect(
        value('plain').layers.single,
        const ShadowLayer(color: 0xFF000000, blurRadius: 3),
      );
      // A list that refers to another token by name is not a literal list.
      expect(index.skipped.map((s) => s.reference), [
        'AppShadows.list',
        'AppShadows.bad',
      ]);
    });
  });

  group('problems', () {
    test('missing file', () {
      final index = build('''
tokens:
  color: { class: AppColors, file: lib/missing.dart }
''');
      expect(index.issues.single.message, contains('lib/missing.dart'));
      expect(index.hasCategory(DesignCategory.color), isFalse);
      expect(index.watchedPaths, contains('/pkg/lib/missing.dart'));
    });

    test('missing class', () {
      write('c', 'class Other {}');
      final index = build('''
tokens:
  color: { class: AppColors, file: lib/c.dart }
''');
      expect(index.issues.single.message, contains('AppColors'));
      expect(index.tokenFilePaths, contains('/pkg/lib/c.dart'));
    });

    test('syntax errors do not throw', () {
      write('c', 'class AppColors { static const a = Color(0xFF000000); ');
      final index = build('''
tokens:
  color: { class: AppColors, file: lib/c.dart }
''');
      expect(index.issues, isEmpty);
    });

    test('empty index', () {
      expect(TokenIndex.empty.length, 0);
      expect(TokenIndex.empty.of(DesignCategory.color), isEmpty);
      expect(TokenIndex.empty.categoryOfClass('AppColors'), isNull);
    });
  });

  group('metadata', () {
    test('reference, import URI and class lookup', () {
      write('s', 'abstract final class AppSpacing { static const md = 16; }');
      final index = build('''
tokens:
  spacing: { class: AppSpacing, file: lib/s.dart }
''');
      final token = index.of(DesignCategory.spacing).single;
      expect(token.reference, 'AppSpacing.md');
      expect(token.importUri, 'package:acme/s.dart');
      expect(index.categoryOfClass('AppSpacing'), DesignCategory.spacing);
      expect(index.tokenClassNames, {'AppSpacing'});
      expect(index.length, 1);
    });

    test('package: URIs are resolved through package_config.json', () {
      provider.newFile('/other/pubspec.yaml', 'name: ds\n');
      provider.newFile(
        '/other/lib/s.dart',
        'abstract final class AppSpacing { static const md = 16; }',
      );
      provider.newFile('/pkg/.dart_tool/package_config.json', '''
{
  "configVersion": 2,
  "packages": [
    {"name": "ds", "rootUri": "../../other", "packageUri": "lib/"},
    {"name": "acme", "rootUri": "../", "packageUri": "lib/"}
  ]
}
''');
      final index = build('''
tokens:
  spacing: { class: AppSpacing, file: 'package:ds/s.dart' }
''');
      expect(index.issues, isEmpty);
      final token = index.of(DesignCategory.spacing).single;
      expect(token.importUri, 'package:ds/s.dart');
    });

    test('unknown package: URI is reported', () {
      provider.newFile('/pkg/.dart_tool/package_config.json', '''
{"configVersion": 2, "packages": []}
''');
      final index = build('''
tokens:
  spacing: { class: AppSpacing, file: 'package:ds/s.dart' }
''');
      expect(index.issues, hasLength(1));
    });
  });

  group('test fixtures', () {
    test('the shared token sources parse completely', () {
      write('app_colors', appColorsSource);
      write('app_spacing', appSpacingSource);
      write('app_radius', appRadiusSource);
      write('app_typography', appTypographySource);
      write('app_shadows', appShadowsSource);
      final index = build('''
tokens:
  color: { class: AppColors, file: lib/app_colors.dart }
  spacing: { class: AppSpacing, file: lib/app_spacing.dart }
  radius: { class: AppRadius, file: lib/app_radius.dart }
  typography: { class: AppTypography, file: lib/app_typography.dart }
  shadow: { class: AppShadows, file: lib/app_shadows.dart }
''');
      expect(index.issues, isEmpty);
      expect(index.skipped, isEmpty);
      expect(index.length, 6 + 5 + 4 + 3 + 2);
    });
  });

  group('exemptions', () {
    ProjectConfig project(String yaml) {
      final config = DtlConfig.parse(
        loadYaml(yaml),
        rootPath: '/pkg',
        source: ConfigSource.standalone,
      );
      return ProjectConfig(
        config: config,
        index: TokenIndex.build(config, provider),
        provider: provider,
      );
    }

    test('reports the reason a file is skipped', () {
      write('c', 'abstract final class AppColors { static const a = 1; }');
      final p = project('''
design_system: { paths: [lib/ds/**], packages: [ds] }
tokens:
  color: { class: AppColors, file: lib/c.dart }
exclude: [lib/x/**]
rules:
  avoid_raw_color: { exclude: [lib/y/**] }
''');
      Object? why(String path, {String? pkg, String? content}) => p
          .exemptionFor(
            path,
            packageName: pkg,
            content: content,
            rule: RuleId.avoidRawColor,
          )
          ?.name;
      expect(why('/pkg/lib/c.dart'), 'tokenFile');
      expect(why('/pkg/lib/a.g.dart'), 'generated');
      expect(why('/pkg/lib/a.dart', content: '// @generated\n'), 'generated');
      expect(why('/pkg/lib/a.dart', pkg: 'ds'), 'designSystemPackage');
      expect(why('/pkg/lib/ds/a.dart'), 'designSystemPath');
      expect(why('/pkg/lib/x/a.dart'), 'excluded');
      expect(why('/pkg/lib/y/a.dart'), 'ruleExcluded');
      expect(why('/pkg/lib/a.dart'), isNull);
    });
  });
}
