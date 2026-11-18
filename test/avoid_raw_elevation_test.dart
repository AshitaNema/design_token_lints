import 'package:analyzer/error/error.dart';
import 'package:design_token_lints/src/config/rule_id.dart';
import 'package:design_token_lints/src/rules/design_token_rule.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/rule_test_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(AvoidRawElevationTest);
    defineReflectiveTests(AvoidRawElevationFixTest);
  });
}

@reflectiveTest
class AvoidRawElevationTest extends DtlRuleTest {
  @override
  RuleId get ruleId => RuleId.avoidRawElevation;

  void test_severity_is_warning() {
    expect(DtlCodes.avoidRawElevation.severity, DiagnosticSeverity.WARNING);
  }

  Future<void> test_material_widgets() async {
    await assertFlagged(
      '''
$testImports
final a = Card(elevation: 3);
final b = Card.outlined(elevation: 4);
final c = Material(elevation: 8);
final d = AppBar(elevation: 5, scrolledUnderElevation: 7);
final e = FloatingActionButton(onPressed: null, elevation: 9);
final f = FloatingActionButton.extended(
  onPressed: null,
  label: SizedBox(),
  elevation: 10,
);
final g = PhysicalModel(elevation: 12, color: Color(0xFF000000));
''',
      ['3', '4', '8', '5', '7', '9', '10', '12'],
    );
  }

  Future<void> test_button_style_from() async {
    await assertFlagged(
      '''
$testImports
final a = ElevatedButton.styleFrom(elevation: 3);
''',
      ['3'],
    );
  }

  Future<void> test_token_zero_and_non_literals_pass() async {
    await assertNoDiagnostics('''
$testImports
final a = Card(elevation: AppElevation.card);
final b = Card(elevation: 0);
final c = Material(elevation: 0.0);
double e() => 3;
final d = Card(elevation: e());
''');
  }

  Future<void> test_allow_list() async {
    writeConfig('''
$defaultConfig
allow:
  elevation: [3]
''');
    await assertFlagged(
      '''
$testImports
final a = Card(elevation: 3);
final b = Card(elevation: 4);
''',
      ['4'],
    );
  }

  Future<void> test_message_names_the_token() async {
    const code =
        '''
$testImports
final a = Card(elevation: 2);
''';
    await assertDiagnostics(code, [
      lint(
        code.indexOf('2)'),
        1,
        messageContainsAll: ["Raw elevation '2'."],
        correctionContains: 'AppElevation.card',
      ),
    ]);
  }
}

@reflectiveTest
class AvoidRawElevationFixTest extends DtlFixTest {
  @override
  RuleId get ruleId => RuleId.avoidRawElevation;

  static const _exact = 'design_token_lints.fix.avoid_raw_elevation';
  static const _nearest = 'design_token_lints.fix.avoid_raw_elevation.nearest';

  Future<void> test_exact_match() async {
    await assertFix(
      '''
$testImports
final a = Card(elevation: 6);
''',
      '''
$testImports
final a = Card(elevation: AppElevation.raised);
''',
      kindId: _exact,
    );
  }

  Future<void> test_nearest_match() async {
    writeConfig('''
$defaultConfig
matching:
  elevation_tolerance: 1
''');
    const code =
        '''
$testImports
final a = Card(elevation: 5);
''';
    final fixes = await fixesFor(code);
    expect(fixes.map((f) => f.kind.id), [_nearest]);
    expect(
      fixes.single.change.message,
      'Replace 5 with nearest token AppElevation.raised (Δ1)',
    );
    expect(apply(fixes.single, code), '''
$testImports
final a = Card(elevation: AppElevation.raised);
''');
  }

  Future<void> test_no_match_has_no_fix() async {
    await assertNoFix('''
$testImports
final a = Card(elevation: 12);
''');
  }
}
