import 'dart:convert';
import 'dart:io';

import 'package:design_token_lints/src/cli/cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fixture_project.dart';

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

  group('coverage', () {
    test('console output', () async {
      final result = await run(['coverage']);
      expect(result.code, ExitCodes.ok);
      expect(result.err, isEmpty);
      expectGolden('coverage.console.txt', result.out);
    });

    test('json output', () async {
      final result = await run(['coverage', '--format', 'json']);
      expect(result.code, ExitCodes.ok);
      final json = jsonDecode(result.out) as Map<String, Object?>;
      expect(json['schemaVersion'], 1);
      expectGolden('coverage.json', result.out);
    });

    test('markdown output', () async {
      final result = await run(['coverage', '--format', 'markdown']);
      expect(result.code, ExitCodes.ok);
      expectGolden('coverage.md', result.out);
    });

    test('output goes to a file and a summary to the console', () async {
      final result = await run([
        'coverage',
        '--format',
        'markdown',
        '--output',
        'out/report.md',
      ]);
      expect(result.code, ExitCodes.ok);
      expect(result.out, startsWith('Design system coverage:'));
      final file = File(p.join(project.root, 'out', 'report.md'));
      expect(
        file.readAsStringSync(),
        startsWith('<!-- design-token-lints -->'),
      );
    });

    test('an explicit path argument', () async {
      final out = StringBuffer();
      final code = await runCli(
        ['coverage', project.root, '--format', 'json'],
        out: out,
        err: StringBuffer(),
        workingDirectory: Directory.systemTemp.path,
      );
      expect(code, ExitCodes.ok);
      expect(out.toString(), contains('"schemaVersion": 1'));
    });

    test('the category filter narrows the measurement', () async {
      final result = await run([
        'coverage',
        '--format',
        'json',
        '--category',
        'color,spacing',
      ]);
      final json = jsonDecode(result.out) as Map<String, Object?>;
      expect((json['categories']! as Map).keys, ['color', 'spacing']);
      final files = json['files']! as List<Object?>;
      for (final file in files.cast<Map<String, Object?>>()) {
        for (final finding
            in (file['findings']! as List).cast<Map<String, Object?>>()) {
          expect(
            finding['rule'],
            anyOf('avoid_raw_color', 'avoid_magic_spacing'),
          );
        }
      }
    });

    test('--fail-under passes when coverage is high enough', () async {
      final result = await run(['coverage', '--fail-under', '10']);
      expect(result.code, ExitCodes.ok);
    });

    test('--fail-under fails when coverage is too low', () async {
      final result = await run(['coverage', '--fail-under', '90']);
      expect(result.code, ExitCodes.belowThreshold);
      expect(result.err, contains('is below the required 90%'));
      expect(result.out, startsWith('Design system coverage:'));
    });

    test(
      'generated, excluded and design-system files are not counted',
      () async {
        final result = await run(['coverage', '--format', 'json']);
        final json = jsonDecode(result.out) as Map<String, Object?>;
        final paths = [
          for (final file
              in (json['files']! as List).cast<Map<String, Object?>>())
            file['path'],
        ];
        expect(paths, ['lib/screens/legacy_checkout.dart']);
      },
    );

    test('a clean project reports full coverage', () async {
      project.delete('lib/screens/legacy_checkout.dart');
      final result = await run(['coverage', '--fail-under', '100']);
      expect(result.code, ExitCodes.ok);
      expect(result.out, contains('Design system coverage: 100%'));
      expect(result.out, contains('no raw values found'));
    });

    test('rule-specific excludes are honoured', () async {
      final config = File(p.join(project.root, 'design_token_lints.yaml'));
      project.write(
        'design_token_lints.yaml',
        '${config.readAsStringSync()}'
            'rules:\n'
            '  avoid_raw_color: { exclude: ["lib/screens/legacy_checkout.dart"] }\n',
      );
      final result = await run(['coverage', '--format', 'json']);
      final json = jsonDecode(result.out) as Map<String, Object?>;
      expect((json['rules']! as Map)['avoid_raw_color'], 0);
      expect((json['rules']! as Map)['avoid_magic_spacing'], greaterThan(0));
    });
  });

  group('exit code 2', () {
    test('no subcommand', () async {
      final result = await run([]);
      expect(result.code, ExitCodes.usage);
      expect(result.err, contains('Usage: design_token_lints'));
    });

    test('unknown subcommand', () async {
      expect((await run(['nope'])).code, ExitCodes.usage);
    });

    test('unknown option', () async {
      expect((await run(['coverage', '--nope'])).code, ExitCodes.usage);
    });

    test('invalid format', () async {
      expect(
        (await run(['coverage', '--format', 'xml'])).code,
        ExitCodes.usage,
      );
    });

    test('invalid threshold', () async {
      for (final value in ['abc', '-1', '101']) {
        final result = await run(['coverage', '--fail-under', value]);
        expect(result.code, ExitCodes.usage, reason: value);
        expect(result.err, contains('--fail-under'));
      }
    });

    test('unknown category', () async {
      final result = await run(['coverage', '--category', 'color,sparkle']);
      expect(result.code, ExitCodes.usage);
      expect(result.err, contains('Unknown category "sparkle"'));
    });

    test('missing directory', () async {
      final result = await run(['coverage', 'does/not/exist']);
      expect(result.code, ExitCodes.usage);
      expect(result.err, contains('is not a directory'));
    });

    test('too many paths', () async {
      expect((await run(['coverage', 'a', 'b'])).code, ExitCodes.usage);
    });

    test('no configuration', () async {
      project.delete('design_token_lints.yaml');
      final result = await run(['coverage']);
      expect(result.code, ExitCodes.usage);
      expect(result.err, contains('No design_token_lints configuration found'));
    });

    test('a configuration error', () async {
      project.write(
        'design_token_lints.yaml',
        'tokens:\n  color: { class: AppColors, file: lib/missing.dart }\n',
      );
      final result = await run(['coverage']);
      expect(result.code, ExitCodes.usage);
      expect(result.err, contains('lib/missing.dart'));
    });

    test('malformed YAML', () async {
      project.write('design_token_lints.yaml', 'tokens: [unclosed');
      final result = await run(['coverage']);
      expect(result.code, ExitCodes.usage);
      expect(result.err, contains('not valid YAML'));
    });
  });

  group('check-config', () {
    test('prints the discovered tokens', () async {
      final result = await run(['check-config']);
      expect(result.code, ExitCodes.ok);
      expectGolden('check_config.txt', result.out);
    });

    test('fails on a configuration error', () async {
      project.write(
        'design_token_lints.yaml',
        'tokens:\n  color: { class: Nope, file: lib/design_system/app_colors.dart }\n',
      );
      final result = await run(['check-config']);
      expect(result.code, ExitCodes.usage);
      expect(result.out, contains('Problems:'));
      expect(result.out, contains('class "Nope" was not found'));
    });

    test('reports skipped token members', () async {
      project.write(
        'lib/design_system/app_spacing.dart',
        'abstract final class AppSpacing {\n'
            '  static const md = 16;\n'
            '  static final dynamic = compute();\n'
            '  static const unknown = other;\n'
            '}\n',
      );
      final result = await run(['check-config']);
      expect(result.out, contains('skipped AppSpacing.unknown'));
    });

    test('without a configuration', () async {
      project.delete('design_token_lints.yaml');
      final result = await run(['check-config']);
      expect(result.code, ExitCodes.usage);
    });
  });

  group('help', () {
    test('top level', () async {
      final result = await run(['--help']);
      expect(result.code, ExitCodes.ok);
      expect(result.out, contains('coverage'));
      expect(result.out, contains('check-config'));
    });

    test('per command', () async {
      final result = await run(['coverage', '--help']);
      expect(result.code, ExitCodes.ok);
      expect(result.out, contains('--fail-under'));
    });
  });
}
