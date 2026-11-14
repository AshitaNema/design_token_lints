import 'dart:convert';
import 'dart:io';

import 'package:design_token_lints/src/cli/cli.dart';
import 'package:design_token_lints/src/config/baseline.dart';
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

  File baselineFile() => File(p.join(project.root, baselineFileName));

  Future<Map<String, Object?>> coverageJson() async {
    final result = await run(['coverage', '--format', 'json']);
    return jsonDecode(result.out) as Map<String, Object?>;
  }

  test('writes the current findings', () async {
    final result = await run(['baseline']);
    expect(result.code, ExitCodes.ok);
    expect(result.err, isEmpty);
    expect(
      result.out,
      startsWith(
        'Wrote design_token_lints.baseline.yaml: 18 raw values in 1 file.\n',
      ),
    );
    expectGolden('baseline.yaml', baselineFile().readAsStringSync());
  });

  test('coverage still counts baselined values, and says so', () async {
    await run(['baseline']);
    final console = await run(['coverage']);
    expect(console.out, startsWith('Design system coverage: 42%'));
    expect(
      console.out,
      endsWith('2 files checked, 18 raw values are in the baseline.\n'),
    );
    final markdown = await run(['coverage', '--format', 'markdown']);
    expect(markdown.out, contains('18 raw values are in the baseline.</sub>'));
    final json = await coverageJson();
    expect(json['baselined'], 18);
  });

  test('a new raw value is not baselined', () async {
    await run(['baseline']);
    project.write('lib/screens/new.dart', '''
import 'package:flutter/material.dart';

final a = EdgeInsets.all(16);
''');
    final json = await coverageJson();
    expect(json['baselined'], 18);
    final files = json['files']! as List<Object?>;
    final added = files.cast<Map<String, Object?>>().singleWhere(
      (f) => f['path'] == 'lib/screens/new.dart',
    );
    final finding = (added['findings']! as List<Object?>).single;
    expect((finding! as Map<String, Object?>)['baselined'], isFalse);
  });

  test('a subdirectory keeps the entries outside it', () async {
    await run(['baseline']);
    project.write('lib/widgets/card.dart', '''
import 'package:flutter/material.dart';

final a = EdgeInsets.all(16);
''');
    final result = await run(['baseline', 'lib/widgets']);
    expect(result.code, ExitCodes.ok);
    expect(
      result.out,
      startsWith(
        'Wrote ../../design_token_lints.baseline.yaml: 19 raw values '
        'in 2 files.\n',
      ),
    );
    final text = baselineFile().readAsStringSync();
    expect(text, contains('"lib/screens/legacy_checkout.dart":'));
    expect(text, contains('"lib/widgets/card.dart":'));
  });

  test('running it again after fixing shrinks the file', () async {
    await run(['baseline']);
    await run(['fix']);
    final result = await run(['baseline']);
    expect(result.out, contains(': 8 raw values in 1 file.'));
  });

  test('a clean project gets an empty baseline', () async {
    await run(['baseline']);
    File(
      p.join(project.root, 'lib', 'screens', 'legacy_checkout.dart'),
    ).deleteSync();
    final result = await run(['baseline']);
    expect(result.out, contains(': 0 raw values in 0 files.'));
    expect(baselineFile().readAsStringSync(), endsWith('files: {}\n'));
  });

  test('a malformed baseline is replaced, with a warning', () async {
    baselineFile().writeAsStringSync('files: [');
    final result = await run(['baseline']);
    expect(result.code, ExitCodes.ok);
    expect(result.err, contains('not valid YAML'));
    expect(baselineFile().readAsStringSync(), contains('version: 1'));
  });

  group('exit code 2', () {
    test('no configuration', () async {
      File(p.join(project.root, 'design_token_lints.yaml')).deleteSync();
      final result = await run(['baseline']);
      expect(result.code, ExitCodes.usage);
      expect(result.err, contains('No design_token_lints configuration'));
      expect(baselineFile().existsSync(), isFalse);
    });

    test('a configuration error writes nothing', () async {
      project.write('design_token_lints.yaml', '''
tokens:
  color: { class: Missing, file: lib/design_system/missing.dart }
''');
      final result = await run(['baseline']);
      expect(result.code, ExitCodes.usage);
      expect(result.err, contains('Nothing was written.'));
      expect(baselineFile().existsSync(), isFalse);
    });
  });

  test('help lists the command', () async {
    final top = await run(['--help']);
    expect(top.out, contains('baseline '));
    final command = await run(['baseline', '--help']);
    expect(command.code, ExitCodes.ok);
  });
}
