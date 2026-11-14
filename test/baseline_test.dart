import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:design_token_lints/src/config/baseline.dart';
import 'package:design_token_lints/src/config/config.dart';
import 'package:design_token_lints/src/config/rule_id.dart';
import 'package:design_token_lints/src/detectors/finding.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/rule_test_base.dart';

/// A finding of [rule] at the initializer expression [source].
Finding finding(RuleId rule, String source) {
  final unit = parseString(content: 'final x = $source;').unit;
  final declaration = unit.declarations.single as TopLevelVariableDeclaration;
  final node = declaration.variables.variables.single.initializer!;
  return Finding(rule: rule, node: node, raw: source);
}

void main() {
  const spacing = RuleId.avoidMagicSpacing;
  const color = RuleId.avoidRawColor;

  group('Baseline.parse', () {
    test('reads accepted findings', () {
      final baseline = Baseline.parse('''
version: 1
files:
  "lib/a.dart":
    avoid_magic_spacing:
      "16": 2
    avoid_raw_color:
      "Color(0xFF123456)": 1
''');
      expect(baseline.issues, isEmpty);
      expect(baseline.total, 3);
      expect(baseline.paths, ['lib/a.dart']);
    });

    test('an empty file accepts nothing', () {
      final baseline = Baseline.parse('');
      expect(baseline.isEmpty, isTrue);
      expect(baseline.issues, isEmpty);
    });

    test('invalid YAML is a warning', () {
      final baseline = Baseline.parse('files: [');
      expect(baseline.isEmpty, isTrue);
      expect(baseline.issues.single.severity, ConfigIssueSeverity.warning);
      expect(baseline.issues.single.message, contains('not valid YAML'));
    });

    test('a document that is not a mapping is a warning', () {
      final baseline = Baseline.parse('- 1');
      expect(baseline.issues.single.message, contains('must be a mapping'));
    });

    test('an unknown version is a warning', () {
      final baseline = Baseline.parse('version: 2\nfiles: {}');
      expect(baseline.isEmpty, isTrue);
      expect(baseline.issues.single.message, contains('reads version 1'));
    });

    test('an unknown rule is a warning and the rest is read', () {
      final baseline = Baseline.parse('''
version: 1
files:
  lib/a.dart:
    no_such_rule: { "16": 1 }
    avoid_magic_spacing: { "16": 1 }
''');
      expect(baseline.total, 1);
      expect(baseline.issues.single.message, contains('"no_such_rule"'));
    });

    test('files that are not a mapping is a warning', () {
      final baseline = Baseline.parse('version: 1\nfiles: [a]');
      expect(baseline.issues.single.message, contains('"files"'));
    });

    test('malformed entries are skipped', () {
      final baseline = Baseline.parse('''
version: 1
files:
  1: { avoid_magic_spacing: { "16": 1 } }
  lib/a.dart: [x]
  lib/b.dart:
    avoid_magic_spacing: [x]
  lib/c.dart:
    avoid_magic_spacing: { "16": zero, "8": 0, 4: 1, "24": 1 }
''');
      expect(baseline.total, 1);
      expect(baseline.issues, isEmpty);
    });
  });

  group('BaselineMatcher', () {
    test('accepts up to the recorded count, in order', () {
      final baseline = Baseline.parse('''
version: 1
files:
  lib/a.dart: { avoid_magic_spacing: { "16": 2 } }
''');
      final matcher = baseline.matcherFor('lib/a.dart');
      expect(matcher.accepts(finding(spacing, '16')), isTrue);
      expect(matcher.accepts(finding(spacing, '16')), isTrue);
      expect(matcher.accepts(finding(spacing, '16')), isFalse);
    });

    test('identity is the rule, the file and the code', () {
      final baseline = Baseline.parse('''
version: 1
files:
  lib/a.dart: { avoid_magic_spacing: { "16": 1 } }
''');
      expect(
        baseline.matcherFor('lib/a.dart').accepts(finding(spacing, '8')),
        isFalse,
      );
      expect(
        baseline.matcherFor('lib/a.dart').accepts(finding(color, '16')),
        isFalse,
      );
      expect(
        baseline.matcherFor('lib/b.dart').accepts(finding(spacing, '16')),
        isFalse,
      );
    });

    test('formatting does not change the identity', () {
      final baseline = Baseline.of({
        'lib/a.dart': [finding(color, 'Color(\n  0xFF123456,\n)')],
      });
      expect(
        baseline
            .matcherFor('lib/a.dart')
            .accepts(finding(color, 'Color(0xFF123456)')),
        isTrue,
      );
    });
  });

  group('serialize', () {
    test('round-trips, sorted', () {
      final baseline = Baseline.of({
        'lib/b.dart': [finding(spacing, '16')],
        'lib/a.dart': [
          finding(color, 'Color(0xFF123456)'),
          finding(spacing, '8'),
          finding(spacing, '16'),
          finding(spacing, '8'),
        ],
      });
      final text = baseline.serialize();
      expect(
        text,
        endsWith('''
version: 1
files:
  "lib/a.dart":
    avoid_raw_color:
      "Color(0xFF123456)": 1
    avoid_magic_spacing:
      "16": 1
      "8": 2
  "lib/b.dart":
    avoid_magic_spacing:
      "16": 1
'''),
      );
      final again = Baseline.parse(text);
      expect(again.issues, isEmpty);
      expect(again.serialize(), text);
    });

    test('an empty baseline', () {
      expect(Baseline.empty.serialize(), endsWith('version: 1\nfiles: {}\n'));
      expect(Baseline.parse(Baseline.empty.serialize()).isEmpty, isTrue);
    });

    test('quotes are escaped', () {
      final baseline = Baseline.of({
        'lib/a.dart': [finding(color, 'colorOf("a: b")')],
      });
      final again = Baseline.parse(baseline.serialize());
      expect(
        again
            .matcherFor('lib/a.dart')
            .accepts(finding(color, 'colorOf("a: b")')),
        isTrue,
      );
    });
  });

  test('mergedWith keeps only the entries it is told to keep', () {
    final old = Baseline.of({
      'lib/keep.dart': [finding(spacing, '16')],
      'lib/redo.dart': [finding(spacing, '16')],
    });
    final fresh = Baseline.of({
      'lib/new.dart': [finding(spacing, '8')],
    });
    final merged = old.mergedWith(fresh, (path) => path == 'lib/keep.dart');
    expect(merged.paths, unorderedEquals(['lib/keep.dart', 'lib/new.dart']));
  });

  defineReflectiveSuite(() {
    defineReflectiveTests(BaselineRuleTest);
  });
}

@reflectiveTest
class BaselineRuleTest extends DtlRuleTest {
  @override
  RuleId get ruleId => RuleId.avoidMagicSpacing;

  void writeBaseline(String yaml) {
    newFile('$testPackageRootPath/$baselineFileName', yaml);
  }

  Future<void> test_baselined_findings_are_not_reported() async {
    writeBaseline('''
version: 1
files:
  lib/test.dart:
    avoid_magic_spacing: { "16": 1, "8": 1 }
''');
    await assertNoDiagnostics('''
$testImports
final a = EdgeInsets.all(16);
final b = SizedBox(height: 8);
''');
  }

  Future<void> test_occurrences_beyond_the_count_are_reported() async {
    writeBaseline('''
version: 1
files:
  lib/test.dart:
    avoid_magic_spacing: { "16": 1 }
''');
    const code =
        '''
$testImports
final a = EdgeInsets.all(16);
final b = EdgeInsets.all(16);
''';
    final second = code.lastIndexOf('16');
    await assertDiagnostics(code, [lint(second, 2)]);
  }

  Future<void> test_new_values_are_reported() async {
    writeBaseline('''
version: 1
files:
  lib/test.dart:
    avoid_magic_spacing: { "16": 1 }
''');
    await assertFlagged(
      '''
$testImports
final a = EdgeInsets.all(16);
final b = EdgeInsets.all(24);
''',
      ['24'],
    );
  }

  Future<void> test_other_files_are_not_affected() async {
    writeBaseline('''
version: 1
files:
  lib/other.dart:
    avoid_magic_spacing: { "16": 1 }
''');
    await assertFlagged(
      '''
$testImports
final a = EdgeInsets.all(16);
''',
      ['16'],
    );
  }

  Future<void> test_a_malformed_baseline_reports_everything() async {
    writeBaseline('files: [');
    await assertFlagged(
      '''
$testImports
final a = EdgeInsets.all(16);
''',
      ['16'],
    );
  }

  Future<void> test_baseline_changes_are_picked_up() async {
    // The test harness only lets Dart files change once analysis has run, so
    // this removes the baseline instead of adding one.
    writeBaseline('''
version: 1
files:
  lib/test.dart:
    avoid_magic_spacing: { "16": 1 }
''');
    const code =
        '''
$testImports
final a = EdgeInsets.all(16);
''';
    await assertNoDiagnostics(code);
    deleteFile('$testPackageRootPath/$baselineFileName');
    await assertFlagged(code, ['16']);
  }
}
