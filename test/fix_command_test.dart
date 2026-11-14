import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart' show Severity;
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

  String read(String relativePath) =>
      File(p.join(project.root, relativePath)).readAsStringSync();

  Future<List<String>> compileErrors(String relativePath) async {
    final path = p.join(project.root, relativePath);
    final collection = AnalysisContextCollection(includedPaths: [path]);
    final result = await collection
        .contextFor(path)
        .currentSession
        .getResolvedUnit(path);
    return [
      for (final d in (result as ResolvedUnitResult).diagnostics)
        if (d.severity == Severity.error) d.message,
    ];
  }

  const legacy = 'lib/screens/legacy_checkout.dart';

  group('fix --dry-run', () {
    test('lists the fixes, changes nothing and exits with 1', () async {
      final before = read(legacy);
      final result = await run(['fix', '--dry-run']);
      expect(result.code, ExitCodes.belowThreshold);
      expect(result.err, isEmpty);
      expectGolden('fix.dry_run.txt', result.out);
      expect(read(legacy), before);
    });

    test('exits with 0 when there is nothing to fix', () async {
      final result = await run(['fix', '--dry-run', 'lib/design_system']);
      expect(result.code, ExitCodes.ok);
      expect(result.out, 'Nothing to fix.\n');
    });
  });

  group('fix', () {
    test('applies exact fixes and adds imports', () async {
      final result = await run(['fix']);
      expect(result.code, ExitCodes.ok);
      expect(result.out, contains('Fixed 9 issues in 1 file.'));
      expectGolden('fix.legacy_checkout.dart.txt', read(legacy));
      expect(await compileErrors(legacy), isEmpty);
    });

    test('a second run has nothing left to fix', () async {
      await run(['fix']);
      final again = await run(['fix']);
      expect(again.code, ExitCodes.ok);
      expect(again.out, startsWith('Nothing to fix.\n'));
    });

    test('--rule limits the fixes', () async {
      final result = await run(['fix', '--rule', 'avoid_magic_spacing']);
      expect(result.code, ExitCodes.ok);
      final fixed = read(legacy);
      expect(fixed, contains('EdgeInsets.all(AppSpacing.md)'));
      expect(fixed, contains('const Color(0xFF1E88E5)'));
      expect(fixed, contains("const Text(\n    'Total',"));
    });

    test('several rules, comma-separated', () async {
      final result = await run([
        'fix',
        '--rule',
        'avoid_magic_spacing, avoid_raw_color',
      ]);
      expect(result.code, ExitCodes.ok);
      final fixed = read(legacy);
      expect(fixed, contains('AppSpacing.md'));
      expect(fixed, contains('color: AppColors.primary'));
      expect(fixed, contains("const Text(\n    'Total',"));
    });

    test('nearest matches are never applied', () async {
      project.write('lib/screens/near.dart', '''
import 'package:flutter/material.dart';

final a = EdgeInsets.all(15);
''');
      project.write('design_token_lints.yaml', '''
${read('design_token_lints.yaml')}
matching:
  spacing_tolerance: 1
''');
      await run(['fix']);
      expect(read('lib/screens/near.dart'), contains('EdgeInsets.all(15)'));
    });

    test('honors ignore comments', () async {
      project.write('lib/screens/ignored.dart', '''
import 'package:flutter/material.dart';

// ignore: design_token_lints/avoid_magic_spacing
final a = EdgeInsets.all(16);
final b = EdgeInsets.all(16); // ignore: design_token_lints/avoid_magic_spacing
final c = EdgeInsets.all(16);
// ignore: avoid_magic_spacing
final d = EdgeInsets.all(16);
final e = Color(0xFF1E88E5); // ignore: design_token_lints/avoid_magic_spacing
''');
      await run(['fix']);
      expect(read('lib/screens/ignored.dart'), '''
import 'package:acme/design_system/app_colors.dart';
import 'package:acme/design_system/app_spacing.dart';
import 'package:flutter/material.dart';

// ignore: design_token_lints/avoid_magic_spacing
final a = EdgeInsets.all(16);
final b = EdgeInsets.all(16); // ignore: design_token_lints/avoid_magic_spacing
final c = EdgeInsets.all(AppSpacing.md);
// ignore: avoid_magic_spacing
final d = EdgeInsets.all(AppSpacing.md);
final e = AppColors.primary; // ignore: design_token_lints/avoid_magic_spacing
''');
    });

    test('honors ignore_for_file', () async {
      const code = '''
// ignore_for_file: design_token_lints/avoid_magic_spacing, other_rule
import 'package:flutter/material.dart';

final a = EdgeInsets.all(16);
''';
      project.write('lib/screens/ignored.dart', code);
      await run(['fix', '--rule', 'avoid_magic_spacing']);
      expect(read('lib/screens/ignored.dart'), code);
    });

    test('a string that looks like an ignore comment does not count', () async {
      project.write('lib/screens/strings.dart', '''
import 'package:flutter/material.dart';

const note = '// ignore: design_token_lints/avoid_magic_spacing';
final a = EdgeInsets.all(16);
''');
      await run(['fix']);
      expect(
        read('lib/screens/strings.dart'),
        contains('EdgeInsets.all(AppSpacing.md)'),
      );
    });

    test('reuses an existing prefixed import', () async {
      project.write('lib/screens/prefixed.dart', '''
import 'package:acme/design_system/app_spacing.dart' as ds;
import 'package:flutter/material.dart';

final a = EdgeInsets.all(16);
final b = ds.AppSpacing.sm;
''');
      await run(['fix']);
      expect(read('lib/screens/prefixed.dart'), '''
import 'package:acme/design_system/app_spacing.dart' as ds;
import 'package:flutter/material.dart';

final a = EdgeInsets.all(ds.AppSpacing.md);
final b = ds.AppSpacing.sm;
''');
    });

    test('leaves a value that matches two tokens for a person', () async {
      project.write('lib/design_system/app_colors.dart', '''
import 'package:flutter/material.dart';

abstract final class AppColors {
  static const Color primary = Color(0xFF1E88E5);
  static const Color brand = Color(0xFF1E88E5);
}
''');
      project.write('lib/screens/ambiguous.dart', '''
import 'package:flutter/material.dart';

final a = Color(0xFF1E88E5);
''');
      final result = await run(['fix', '--rule', 'avoid_raw_color']);
      expect(read('lib/screens/ambiguous.dart'), contains('Color(0xFF1E88E5)'));
      expect(
        result.out,
        contains(
          'Not fixed, more than one token matches (choose one in your IDE):\n'
          '  lib/screens/ambiguous.dart:3:11  Color(0xFF1E88E5): '
          'AppColors.primary, AppColors.brand\n',
        ),
      );
    });

    test('a fix inside another fix is left for the next run', () async {
      project.write('lib/design_system/app_colors.dart', '''
import 'package:flutter/material.dart';

abstract final class AppColors {
  static const Color shadow = Color(0x1A000000);
}
''');
      project.write('lib/screens/nested.dart', '''
import 'package:flutter/material.dart';

final a = [
  BoxShadow(color: Color(0x1A000000), blurRadius: 8, offset: Offset(0, 2)),
];
''');
      final result = await run([
        'fix',
        '--rule',
        'avoid_raw_shadow,avoid_raw_color',
      ]);
      expect(
        read('lib/screens/nested.dart'),
        contains('final a = AppShadows.card;'),
      );
      expect(
        result.out,
        contains('Not fixed, inside another fix (run the command again):\n'),
      );
      expect(
        result.out,
        contains(
          '  lib/screens/nested.dart:4:20  Color(0x1A000000): '
          'AppColors.shadow\n',
        ),
      );
    });
  });

  group('fix exit code 2', () {
    test('unknown rule', () async {
      final result = await run(['fix', '--rule', 'no_such_rule']);
      expect(result.code, ExitCodes.usage);
      expect(result.err, contains('Unknown rule "no_such_rule"'));
    });

    test('no configuration', () async {
      File(p.join(project.root, 'design_token_lints.yaml')).deleteSync();
      final result = await run(['fix']);
      expect(result.code, ExitCodes.usage);
      expect(result.err, contains('No design_token_lints configuration'));
    });

    test('a configuration error changes nothing', () async {
      final before = read(legacy);
      project.write('design_token_lints.yaml', '''
tokens:
  color: { class: Missing, file: lib/design_system/missing.dart }
''');
      final result = await run(['fix']);
      expect(result.code, ExitCodes.usage);
      expect(result.err, contains('Nothing was changed.'));
      expect(read(legacy), before);
    });
  });

  test('help lists the command', () async {
    final top = await run(['--help']);
    expect(top.out, contains('fix '));
    final command = await run(['fix', '--help']);
    expect(command.code, ExitCodes.ok);
    expect(command.out, contains('--dry-run'));
    expect(command.out, contains('--rule'));
  });
}
