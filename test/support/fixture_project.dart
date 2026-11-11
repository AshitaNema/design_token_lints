import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fake_flutter.dart';

/// A copy of a fixture project in a temporary directory, with a package config
/// that resolves `package:flutter/material.dart` to the fake Flutter.
final class FixtureProject {
  FixtureProject._(this.root, this._temp);

  /// Copies `test/fixtures/<name>` and prepares it for analysis.
  static FixtureProject create(String name) {
    final temp = Directory.systemTemp.createTempSync('dtl_fixture_');
    final root = p.join(temp.path, name);
    _copy(Directory(p.join('test', 'fixtures', name)), Directory(root));

    final flutter = p.join(temp.path, '_packages', 'flutter', 'lib');
    Directory(flutter).createSync(recursive: true);
    File(
      p.join(flutter, 'material.dart'),
    ).writeAsStringSync(fakeFlutterMaterial);

    final config = File(p.join(root, '.dart_tool', 'package_config.json'));
    config.parent.createSync(recursive: true);
    config.writeAsStringSync('''
{
  "configVersion": 2,
  "packages": [
    {
      "name": "flutter",
      "rootUri": "${Uri.directory(p.join(temp.path, '_packages', 'flutter'))}",
      "packageUri": "lib/",
      "languageVersion": "3.11"
    },
    {
      "name": "$name",
      "rootUri": "../",
      "packageUri": "lib/",
      "languageVersion": "3.11"
    }
  ]
}
''');
    return FixtureProject._(root, temp);
  }

  /// The project directory.
  final String root;

  final Directory _temp;

  /// Replaces the file at [relativePath] with [content].
  void write(String relativePath, String content) {
    final file = File(p.join(root, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  /// Deletes the file at [relativePath].
  void delete(String relativePath) =>
      File(p.join(root, relativePath)).deleteSync();

  /// Removes the temporary directory.
  void dispose() => _temp.deleteSync(recursive: true);

  static void _copy(Directory from, Directory to) {
    to.createSync(recursive: true);
    for (final entity in from.listSync()) {
      final target = p.join(to.path, p.basename(entity.path));
      if (entity is Directory) {
        _copy(entity, Directory(target));
      } else if (entity is File) {
        entity.copySync(target);
      }
    }
  }
}

/// Compares [actual] with `test/fixtures/golden/[name]`.
///
/// Run the tests with `UPDATE_GOLDENS=1` to rewrite the golden files.
void expectGolden(String name, String actual) {
  final file = File(p.join('test', 'fixtures', 'golden', name));
  if (Platform.environment['UPDATE_GOLDENS'] == '1') {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(actual);
    return;
  }
  expect(
    file.existsSync(),
    isTrue,
    reason: 'Missing golden ${file.path}. Run with UPDATE_GOLDENS=1.',
  );
  expect(actual, file.readAsStringSync());
}
