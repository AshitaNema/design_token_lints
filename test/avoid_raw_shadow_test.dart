import 'package:analyzer/error/error.dart';
import 'package:design_token_lints/src/config/rule_id.dart';
import 'package:design_token_lints/src/rules/design_token_rule.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/rule_test_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(AvoidRawShadowTest);
    defineReflectiveTests(AvoidRawShadowFixTest);
  });
}

@reflectiveTest
class AvoidRawShadowTest extends DtlRuleTest {
  @override
  RuleId get ruleId => RuleId.avoidRawShadow;

  void test_severity_is_info() {
    expect(DtlCodes.avoidRawShadow.severity, DiagnosticSeverity.INFO);
  }

  Future<void> test_single_shadow() async {
    await assertFlagged(
      '''
$testImports
const a = BoxShadow(blurRadius: 6);
''',
      ['BoxShadow(blurRadius: 6)'],
    );
  }

  Future<void> test_list_is_reported_once() async {
    await assertFlagged(
      '''
$testImports
const a = [BoxShadow(blurRadius: 6), BoxShadow(blurRadius: 12)];
''',
      ['[BoxShadow(blurRadius: 6), BoxShadow(blurRadius: 12)]'],
    );
  }

  Future<void> test_list_in_decoration() async {
    await assertFlagged(
      '''
$testImports
const a = BoxDecoration(boxShadow: [BoxShadow(blurRadius: 6)]);
''',
      ['[BoxShadow(blurRadius: 6)]'],
    );
  }

  Future<void> test_const_list_includes_the_keyword() async {
    await assertFlagged(
      '''
$testImports
final a = const [BoxShadow(blurRadius: 6)];
''',
      ['const [BoxShadow(blurRadius: 6)]'],
    );
  }

  Future<void> test_token_and_other_lists_are_allowed() async {
    await assertNoDiagnostics('''
$testImports
const a = AppShadows.card;
const b = [1, 2, 3];
const c = <BoxShadow>[];
''');
  }

  Future<void> test_design_system_path_is_exempt() async {
    final path = '$testPackageRootPath/lib/design_system/extra.dart';
    newFile(path, '''
import 'package:flutter/material.dart';
const a = BoxShadow(blurRadius: 6);
''');
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_no_config_is_silent() async {
    deleteConfig();
    await assertNoDiagnostics('''
$testImports
const a = BoxShadow(blurRadius: 6);
''');
  }

  Future<void> test_ignore_comment() async {
    await assertNoDiagnostics('''
$testImports
// ignore: avoid_raw_shadow
const a = BoxShadow(blurRadius: 6);
''');
  }
}

@reflectiveTest
class AvoidRawShadowFixTest extends DtlFixTest {
  @override
  RuleId get ruleId => RuleId.avoidRawShadow;

  static const _exact = 'design_token_lints.fix.avoid_raw_shadow';

  Future<void> test_list_matches_list_token() async {
    await assertFix(
      '''
$testImports
final a = BoxDecoration(
  boxShadow: [
    BoxShadow(color: Color(0x1A000000), blurRadius: 8, offset: Offset(0, 2)),
  ],
);
''',
      '''
$testImports
final a = BoxDecoration(
  boxShadow: AppShadows.card,
);
''',
      kindId: _exact,
    );
  }

  Future<void> test_const_list_is_replaced_with_its_keyword() async {
    await assertFix(
      '''
$testImports
final a = const [
  BoxShadow(color: Color(0x1A000000), blurRadius: 8, offset: Offset(0, 2)),
];
''',
      '''
$testImports
final a = AppShadows.card;
''',
      kindId: _exact,
    );
  }

  Future<void> test_argument_order_and_defaults_do_not_matter() async {
    await assertFix(
      '''
$testImports
final a = [
  BoxShadow(
    offset: Offset(0, 2),
    spreadRadius: 0,
    blurRadius: 8,
    color: Color(0x1A000000),
  ),
];
''',
      '''
$testImports
final a = AppShadows.card;
''',
      kindId: _exact,
    );
  }

  Future<void> test_single_shadow_matches_single_token() async {
    await assertFix(
      '''
$testImports
const a = BoxShadow(color: Color(0x33000000), blurRadius: 4);
''',
      '''
$testImports
const a = AppShadows.single;
''',
      kindId: _exact,
    );
  }

  Future<void> test_single_shadow_does_not_match_list_token() async {
    await assertNoFix('''
$testImports
const a = BoxShadow(color: Color(0x1A000000), blurRadius: 8, offset: Offset(0, 2));
''');
  }

  Future<void> test_different_values_have_no_fix() async {
    await assertNoFix('''
$testImports
final a = [BoxShadow(color: Color(0x1A000000), blurRadius: 9, offset: Offset(0, 2))];
''');
  }

  Future<void> test_non_literal_values_have_no_fix() async {
    await assertNoFix('''
$testImports
List<BoxShadow> f(double blur) => [BoxShadow(blurRadius: blur)];
''');
  }

  Future<void> test_extra_layer_has_no_fix() async {
    await assertNoFix('''
$testImports
final a = [
  BoxShadow(color: Color(0x1A000000), blurRadius: 8, offset: Offset(0, 2)),
  BoxShadow(blurRadius: 1),
];
''');
  }
}
