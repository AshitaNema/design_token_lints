import 'package:analyzer/file_system/memory_file_system.dart';
import 'package:design_token_lints/src/config/config.dart';
import 'package:design_token_lints/src/config/rule_id.dart';
import 'package:design_token_lints/src/design_tokens/drift.dart';
import 'package:design_token_lints/src/design_tokens/dtcg.dart';
import 'package:design_token_lints/src/tokens/token_index.dart';
import 'package:design_token_lints/src/tokens/token_value.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  DesignToken token(String type, Object? value) =>
      DesignToken(path: const ['t'], type: type, value: value);

  TokenValue convert(DesignCategory category, String type, Object? value) =>
      designValueOf(category, token(type, value));

  Matcher fails(String message) => throwsA(
    isA<FormatException>().having((e) => e.message, 'message', message),
  );

  Map<String, Object?> px(num value) => {'value': value, 'unit': 'px'};

  group('camelCaseName', () {
    test('joins segments and words', () {
      expect(camelCaseName('primary'), 'primary');
      expect(camelCaseName('brand.primary'), 'brandPrimary');
      expect(camelCaseName('brand-primary'), 'brandPrimary');
      expect(camelCaseName('text_on surface'), 'textOnSurface');
      expect(camelCaseName('Brand.Primary'), 'brandPrimary');
      expect(camelCaseName('blue.500'), 'blue500');
    });

    test('is null when no identifier results', () {
      expect(camelCaseName('4'), isNull);
      expect(camelCaseName('100.x'), isNull);
      expect(camelCaseName('-'), isNull);
      expect(camelCaseName('a+b'), isNull);
    });
  });

  group('colors', () {
    const c = DesignCategory.color;

    test('srgb components and alpha', () {
      expect(
        convert(c, 'color', {
          'colorSpace': 'srgb',
          'components': [1, 0.5, 0],
          'alpha': 0.5,
        }),
        const ColorValue(0x80FF8000),
      );
      expect(
        convert(c, 'color', {
          'colorSpace': 'srgb',
          'components': ['none', 0, 1],
        }),
        const ColorValue(0xFF0000FF),
      );
    });

    test('another color space through its hex fallback', () {
      expect(
        convert(c, 'color', {
          'colorSpace': 'oklch',
          'components': [0.5, 0.1, 200],
          'hex': '#1E88E5',
          'alpha': 1,
        }),
        const ColorValue(0xFF1E88E5),
      );
      expect(
        () => convert(c, 'color', {
          'colorSpace': 'display-p3',
          'components': [1, 0, 0],
        }),
        fails(
          'the color space "display-p3" can only be compared through a '
          '"hex" fallback',
        ),
      );
    });

    test('hex strings as older exporters write them', () {
      expect(convert(c, 'color', '#1e88e5'), const ColorValue(0xFF1E88E5));
      expect(convert(c, 'color', '#1E88E580'), const ColorValue(0x801E88E5));
      expect(() => convert(c, 'color', 'blue'), fails('"blue" is not a color'));
    });

    test('out-of-range components', () {
      expect(
        () => convert(c, 'color', {
          'colorSpace': 'srgb',
          'components': [2, 0, 0],
        }),
        fails('red 2.0 is outside 0 to 1'),
      );
    });
  });

  group('numbers', () {
    test('px dimensions and plain numbers', () {
      expect(
        convert(DesignCategory.spacing, 'dimension', px(16)),
        const NumberValue(16),
      );
      expect(
        convert(DesignCategory.elevation, 'number', 2),
        const NumberValue(2),
      );
    });

    test('a number that is not a number', () {
      expect(
        () => convert(DesignCategory.elevation, 'number', '2'),
        fails('value is not a number'),
      );
    });

    test('components have no values to compare', () {
      expect(
        () => convert(DesignCategory.component, 'number', 1),
        fails('component tokens cannot be compared'),
      );
    });

    test('rem and other units are not compared', () {
      expect(
        () => convert(DesignCategory.radius, 'dimension', {
          'value': 1,
          'unit': 'rem',
        }),
        fails('value is in "rem"; only px dimensions can be compared'),
      );
    });

    test('types must fit the category', () {
      expect(
        () => convert(DesignCategory.iconSize, 'color', '#000000'),
        fails(
          'a color token cannot be compared with icon_size tokens '
          '(expected dimension or number)',
        ),
      );
      expect(
        () => designValueOf(
          DesignCategory.spacing,
          const DesignToken(path: ['t'], type: null, value: 4),
        ),
        fails(r'the token has no $type'),
      );
    });
  });

  group('typography', () {
    test('size, weight names, line height and letter spacing', () {
      expect(
        convert(DesignCategory.typography, 'typography', {
          'fontFamily': 'Inter',
          'fontSize': px(22),
          'fontWeight': 'semi-bold',
          'lineHeight': 1.4,
          'letterSpacing': px(0.5),
        }),
        const TextStyleValue(
          fontSize: 22,
          fontWeight: 600,
          height: 1.4,
          letterSpacing: 0.5,
        ),
      );
      expect(
        convert(DesignCategory.typography, 'typography', {'fontWeight': 350}),
        const TextStyleValue(fontWeight: 350),
      );
    });

    test('an unknown weight', () {
      expect(
        () => convert(DesignCategory.typography, 'typography', {
          'fontWeight': 'chunky',
        }),
        fails('fontWeight "chunky" is not a weight'),
      );
      expect(
        () => convert(DesignCategory.typography, 'typography', 'x'),
        fails('value is not an object'),
      );
    });
  });

  group('shadows', () {
    final layer = {
      'color': {
        'colorSpace': 'srgb',
        'components': [0, 0, 0],
        'alpha': 0.1,
      },
      'offsetX': px(0),
      'offsetY': px(2),
      'blur': px(8),
      'spread': px(0),
    };
    const expected = ShadowLayer(color: 0x1A000000, blurRadius: 8, dy: 2);

    test('a single shadow or a list', () {
      expect(
        convert(DesignCategory.shadow, 'shadow', layer),
        const ShadowValue([expected], isList: false),
      );
      expect(
        convert(DesignCategory.shadow, 'shadow', [layer, layer]),
        const ShadowValue([expected, expected], isList: true),
      );
    });

    test('inset shadows are not compared', () {
      expect(
        () =>
            convert(DesignCategory.shadow, 'shadow', {...layer, 'inset': true}),
        fails('inset shadows have no Flutter BoxShadow'),
      );
    });
  });

  group('sameValue', () {
    test('radius tokens compare by number', () {
      expect(sameValue(const RadiusValue(8), const NumberValue(8)), isTrue);
      expect(
        sameValue(const BorderRadiusValue(8), const NumberValue(9)),
        isFalse,
      );
      expect(sameValue(const ColorValue(1), const NumberValue(1)), isFalse);
    });

    test('shadows compare by layers, list or not', () {
      const layer = ShadowLayer(color: 1);
      expect(
        sameValue(
          const ShadowValue([layer], isList: true),
          const ShadowValue([layer], isList: false),
        ),
        isTrue,
      );
      expect(
        sameValue(
          const ShadowValue([layer], isList: true),
          const ShadowValue([layer, layer], isList: true),
        ),
        isFalse,
      );
      expect(
        sameValue(
          const ShadowValue([layer], isList: true),
          const ShadowValue([ShadowLayer(color: 2)], isList: true),
        ),
        isFalse,
      );
    });
  });

  group('compareDesignTokens', () {
    late TokenIndex index;

    setUp(() {
      final provider = MemoryResourceProvider()
        ..newFile('/pkg/pubspec.yaml', 'name: acme\n')
        ..newFile('/pkg/lib/colors.dart', '''
abstract final class AppColors {
  static const brandPrimary = Color(0xFF1E88E5);
  static const surface = Color(0xFFFAFAFA);
  static const legacy = Color(0xFF123456);
}
''')
        ..newFile('/pkg/lib/spacing.dart', '''
abstract final class AppSpacing {
  static const xs = 4.0;
  static const md = 16.0;
}
''');
      index = TokenIndex.build(
        DtlConfig.parse(
          loadYaml('''
tokens:
  color: { class: AppColors, file: lib/colors.dart }
  spacing: { class: AppSpacing, file: lib/spacing.dart }
'''),
          rootPath: '/pkg',
          source: ConfigSource.standalone,
        ),
        provider,
      );
    });

    test('reports matches, differences and what is missing', () {
      final file = DesignTokenFile.parse(r'''
{
  "color": {
    "$type": "color",
    "brand": { "primary": { "$value": "#1E88E5" } },
    "surface": { "$value": "#FAFAFB" },
    "accent": { "$value": "#FF9900" }
  },
  "space": {
    "$type": "dimension",
    "4": { "$value": { "value": 4, "unit": "px" } },
    "16": { "$value": { "value": 16, "unit": "px" } },
    "32": { "$value": { "value": 2, "unit": "rem" } }
  }
}''');
      final report = compareDesignTokens(file, index, const {
        DesignCategory.color: DesignTokenGroup(group: 'color'),
        DesignCategory.spacing: DesignTokenGroup(
          group: 'space',
          names: {'4': 'xs', '16': 'md'},
        ),
      });
      expect(report.matching, 3);
      expect(report.inSync, isFalse);
      expect(
        report.different.map(
          (i) => (i.dartReference, i.designValue, i.dartValue),
        ),
        [('AppColors.surface', '0xFFFAFAFB', '0xFFFAFAFA')],
      );
      expect(report.missingInDart.map((i) => (i.designPath, i.dartReference)), [
        ('color.accent', 'AppColors.accent'),
      ]);
      expect(
        report.missingInDesign.map((i) => (i.dartReference, i.dartValue)),
        [('AppColors.legacy', '0xFF123456')],
      );
      expect(report.skipped.map((p) => '$p'), [
        'space.32: no Dart name can be derived; add it under "names"',
      ]);
    });

    test('in sync', () {
      final file = DesignTokenFile.parse(
        r'''
{ "space": { "$type": "number", "xs": { "$value": 4 }, "md": { "$value": 16 } } }''',
      );
      final report = compareDesignTokens(file, index, const {
        DesignCategory.spacing: DesignTokenGroup(group: 'space'),
      });
      expect(report.inSync, isTrue);
      expect(report.matching, 2);
    });
  });

  test('describeValue', () {
    expect(describeValue(const NumberValue(1.5)), '1.5');
    expect(describeValue(const RadiusValue(8)), '8');
    expect(describeValue(const BorderRadiusValue(4)), '4');
    expect(describeValue(const ColorValue(0xFF000001)), '0xFF000001');
    expect(
      describeValue(
        const TextStyleValue(
          fontSize: 12,
          fontWeight: 400,
          height: 1.2,
          letterSpacing: 0,
        ),
      ),
      'fontSize 12, fontWeight 400, height 1.2, letterSpacing 0',
    );
    expect(
      describeValue(
        const ShadowValue([
          ShadowLayer(color: 0x1A000000, blurRadius: 8, dy: 2),
        ], isList: true),
      ),
      '0x1A000000 blur 8 spread 0 offset (0, 2)',
    );
  });
}
