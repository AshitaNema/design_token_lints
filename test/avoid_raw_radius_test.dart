import 'package:analyzer/error/error.dart';
import 'package:design_token_lints/src/config/rule_id.dart';
import 'package:design_token_lints/src/rules/design_token_rule.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/rule_test_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(AvoidRawRadiusTest);
    defineReflectiveTests(AvoidRawRadiusFixTest);
  });
}

@reflectiveTest
class AvoidRawRadiusTest extends DtlRuleTest {
  @override
  RuleId get ruleId => RuleId.avoidRawRadius;

  void test_severity_is_warning() {
    expect(DtlCodes.avoidRawRadius.severity, DiagnosticSeverity.WARNING);
  }

  Future<void> test_border_radius_circular() async {
    await assertFlagged(
      '''
$testImports
const a = BorderRadius.circular(12);
''',
      ['BorderRadius.circular(12)'],
    );
  }

  Future<void> test_border_radius_all_is_reported_once() async {
    await assertFlagged(
      '''
$testImports
const a = BorderRadius.all(Radius.circular(12));
''',
      ['BorderRadius.all(Radius.circular(12))'],
    );
  }

  Future<void> test_standalone_radius() async {
    await assertFlagged(
      '''
$testImports
const a = Radius.circular(12);
''',
      ['Radius.circular(12)'],
    );
  }

  Future<void> test_border_radius_only_reports_each_corner() async {
    await assertFlagged(
      '''
$testImports
const a = BorderRadius.only(
  topLeft: Radius.circular(12),
  bottomRight: Radius.circular(10),
);
''',
      ['Radius.circular(12)', 'Radius.circular(10)'],
    );
  }

  Future<void> test_zero_and_non_literal_are_allowed() async {
    await assertNoDiagnostics('''
$testImports
const a = BorderRadius.circular(0);
const b = BorderRadius.all(Radius.circular(AppRadius.md));
BorderRadius c(double r) => BorderRadius.circular(r);
const d = AppRadius.xlBorder;
''');
  }

  Future<void> test_allow_list() async {
    writeConfig('''
$defaultConfig
allow:
  radius: [999]
''');
    await assertFlagged(
      '''
$testImports
const a = BorderRadius.circular(999);
const b = BorderRadius.circular(998);
''',
      ['BorderRadius.circular(998)'],
    );
  }

  Future<void> test_design_system_path_is_exempt() async {
    final path = '$testPackageRootPath/lib/design_system/extra.dart';
    newFile(path, '''
import 'package:flutter/material.dart';
const a = BorderRadius.circular(12);
''');
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_no_config_is_silent() async {
    deleteConfig();
    await assertNoDiagnostics('''
$testImports
const a = BorderRadius.circular(12);
''');
  }

  Future<void> test_ignore_comment() async {
    await assertNoDiagnostics('''
$testImports
// ignore: avoid_raw_radius
const a = BorderRadius.circular(12);
''');
  }
}

@reflectiveTest
class AvoidRawRadiusFixTest extends DtlFixTest {
  @override
  RuleId get ruleId => RuleId.avoidRawRadius;

  static const _exact = 'design_token_lints.fix.avoid_raw_radius';
  static const _nearest = 'design_token_lints.fix.avoid_raw_radius.nearest';

  Future<void> test_double_token_keeps_the_constructor() async {
    await assertFix(
      '''
$testImports
const a = BorderRadius.circular(8);
''',
      '''
$testImports
const a = BorderRadius.circular(AppRadius.md);
''',
      kindId: _exact,
    );
  }

  Future<void> test_border_radius_token_replaces_the_expression() async {
    await assertFix(
      '''
$testImports
const a = BorderRadius.circular(24);
''',
      '''
$testImports
const a = AppRadius.xlBorder;
''',
      kindId: _exact,
    );
  }

  Future<void> test_radius_token_replaces_the_expression() async {
    await assertFix(
      '''
$testImports
const a = Radius.circular(16);
''',
      '''
$testImports
const a = AppRadius.lgRadius;
''',
      kindId: _exact,
    );
  }

  Future<void> test_all_with_radius_token_replaces_the_inner_radius() async {
    await assertFix(
      '''
$testImports
const a = BorderRadius.all(Radius.circular(16));
''',
      '''
$testImports
const a = BorderRadius.all(AppRadius.lgRadius);
''',
      kindId: _exact,
    );
  }

  Future<void> test_all_with_double_token_keeps_both_constructors() async {
    await assertFix(
      '''
$testImports
const a = BorderRadius.all(Radius.circular(8));
''',
      '''
$testImports
const a = BorderRadius.all(Radius.circular(AppRadius.md));
''',
      kindId: _exact,
    );
  }

  Future<void> test_all_with_border_radius_token_replaces_everything() async {
    await assertFix(
      '''
$testImports
const a = BorderRadius.all(Radius.circular(24));
''',
      '''
$testImports
const a = AppRadius.xlBorder;
''',
      kindId: _exact,
    );
  }

  Future<void> test_corner_of_only() async {
    await assertFix(
      '''
$testImports
const a = BorderRadius.only(topLeft: Radius.circular(4));
''',
      '''
$testImports
const a = BorderRadius.only(topLeft: Radius.circular(AppRadius.sm));
''',
      kindId: _exact,
    );
  }

  Future<void> test_no_match_has_no_fix() async {
    await assertNoFix('''
$testImports
const a = BorderRadius.circular(11);
''');
  }

  Future<void> test_nearest_within_tolerance() async {
    writeConfig('''
$defaultConfig
matching:
  radius_tolerance: 1
''');
    const code =
        '''
$testImports
const a = BorderRadius.circular(7);
''';
    final fixes = await fixesFor(code);
    expect(fixes.map((f) => f.kind.id), [_nearest]);
    expect(apply(fixes.single, code), '''
$testImports
const a = BorderRadius.circular(AppRadius.md);
''');
  }

  Future<void> test_import_is_added() async {
    await assertFix(
      '''
import 'package:flutter/material.dart';
const a = BorderRadius.circular(8);
''',
      '''
import 'package:flutter/material.dart';
import 'package:test/design_system/app_radius.dart';
const a = BorderRadius.circular(AppRadius.md);
''',
      kindId: _exact,
    );
  }
}
