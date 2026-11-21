import 'dart:convert';
import 'dart:io';

import 'package:design_token_lints/src/cli/cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fixture_project.dart';

/// The fixture's spacing scale (`AppSpacing`: 4, 8, 16, 24) in the Design
/// Tokens Format Module.
const _spacing = r'''
"space": {
  "$type": "dimension",
  "xs": { "$value": { "value": 4, "unit": "px" } },
  "sm": { "$value": { "value": 8, "unit": "px" } },
  "md": { "$value": { "value": 16, "unit": "px" } },
  "lg": { "$value": { "value": 24, "unit": "px" } }
}''';

void main() {
  late FixtureProject project;

  setUp(() => project = FixtureProject.create('acme'));
  tearDown(() => project.dispose());

  Future<({int code, String out, String err})> run(List<String> args) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runCli(
      args,
      out: out,
      err: err,
      workingDirectory: project.root,
    );
    return (code: code, out: out.toString(), err: err.toString());
  }

  void configure(String map) {
    final config = File(
      p.join(project.root, 'design_token_lints.yaml'),
    ).readAsStringSync();
    project.write('design_token_lints.yaml', '''
$config
design_tokens:
  file: design/tokens.json
  map:
$map
''');
  }

  test('in sync', () async {
    project.write('design/tokens.json', '{ $_spacing }');
    configure('    spacing: { group: space }');
    final result = await run(['check-tokens']);
    expect(result.code, ExitCodes.ok);
    expect(
      result.out,
      'Compared design/tokens.json with the Dart tokens: 4 match.\n',
    );
  });

  test('drift', () async {
    project.write('design/tokens.json', r'''
{
  "color": {
    "$type": "color",
    "primary": { "$value": { "colorSpace": "srgb", "components": [0.1176, 0.5333, 0.898] } },
    "surface": { "$value": "#FAFAFB" },
    "warning": { "$value": "#FF9900" },
    "accent": { "$value": { "colorSpace": "display-p3", "components": [1, 0, 0] } },
    "danger": { "$value": "{color.missing}" }
  }
}''');
    configure('    color: { group: color }');
    final result = await run(['check-tokens']);
    expect(result.code, ExitCodes.belowThreshold);
    expect(result.out, '''
Compared design/tokens.json with the Dart tokens: 1 match, 1 differ, 1 missing in Dart, 2 missing in the design file.

Different values:
  AppColors.surface  design 0xFFFAFAFB (color.surface), Dart 0xFFFAFAFA

Missing in Dart:
  AppColors.warning  for color.warning (0xFFFF9900)

Missing in the design file:
  AppColors.onPrimary (0xFFFFFFFF)
  AppColors.danger (0xFFD32F2F)

Not compared:
  color.danger: the reference {color.missing} does not name a token
  color.accent: the color space "display-p3" can only be compared through a "hex" fallback
''');
  });

  test('json output', () async {
    project.write('design/tokens.json', '{ $_spacing }');
    configure('    spacing: { group: space }');
    project.write('lib/design_system/app_spacing.dart', '''
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 20;
}
''');
    final result = await run(['check-tokens', '--format', 'json']);
    expect(result.code, ExitCodes.belowThreshold);
    final json = jsonDecode(result.out) as Map<String, Object?>;
    expect(json['schemaVersion'], 1);
    expect(json['inSync'], isFalse);
    expect(json['matching'], 3);
    expect(json['different'], [
      {
        'category': 'spacing',
        'designPath': 'space.lg',
        'dartReference': 'AppSpacing.lg',
        'designValue': '24',
        'dartValue': '20',
      },
    ]);
    expect(json['missingInDart'], isEmpty);
    expect(json['skipped'], isEmpty);
  });

  group('exit code 2', () {
    test('no configuration', () async {
      File(p.join(project.root, 'design_token_lints.yaml')).deleteSync();
      final result = await run(['check-tokens']);
      expect(result.code, ExitCodes.usage);
      expect(result.err, contains('No design_token_lints configuration'));
    });

    test('no design_tokens section', () async {
      final result = await run(['check-tokens']);
      expect(result.code, ExitCodes.usage);
      expect(result.err, contains('no design_tokens section'));
    });

    test('a missing file', () async {
      configure('    spacing: { group: space }');
      final result = await run(['check-tokens']);
      expect(result.code, ExitCodes.usage);
      expect(result.err, contains('file "design/tokens.json" was not found'));
    });

    test('a category without Dart tokens', () async {
      project.write('design/tokens.json', '{ $_spacing }');
      configure('    icon_size: { group: space }');
      final result = await run(['check-tokens']);
      expect(result.code, ExitCodes.usage);
      expect(
        result.err,
        contains(
          'tokens.icon_size is not configured or its class was not '
          'found',
        ),
      );
    });

    test('a file that is not JSON', () async {
      project.write('design/tokens.json', '{');
      configure('    spacing: { group: space }');
      final result = await run(['check-tokens']);
      expect(result.code, ExitCodes.usage);
      expect(result.err, contains('design/tokens.json: not valid JSON'));
    });

    test('a configuration error', () async {
      project.write('design/tokens.json', '{ $_spacing }');
      project.write('design_token_lints.yaml', '''
tokens:
  color: { class: Missing, file: lib/design_system/missing.dart }
design_tokens: { file: design/tokens.json, map: { color: { group: c } } }
''');
      final result = await run(['check-tokens']);
      expect(result.code, ExitCodes.usage);
      expect(result.err, contains('was not found'));
    });
  });

  test('help lists the command', () async {
    final top = await run(['--help']);
    expect(top.out, contains('check-tokens'));
    final command = await run(['check-tokens', '--help']);
    expect(command.code, ExitCodes.ok);
    expect(command.out, contains('--format'));
  });
}
