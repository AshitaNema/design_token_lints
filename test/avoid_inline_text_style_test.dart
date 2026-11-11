import 'package:analyzer/error/error.dart';
import 'package:design_token_lints/src/config/rule_id.dart';
import 'package:design_token_lints/src/rules/design_token_rule.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/rule_test_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(AvoidInlineTextStyleTest);
    defineReflectiveTests(AvoidInlineTextStyleFixTest);
  });
}

@reflectiveTest
class AvoidInlineTextStyleTest extends DtlRuleTest {
  @override
  RuleId get ruleId => RuleId.avoidInlineTextStyle;

  void test_severity_is_warning() {
    expect(DtlCodes.avoidInlineTextStyle.severity, DiagnosticSeverity.WARNING);
  }

  Future<void> test_text_style_constructor() async {
    await assertFlagged(
      '''
$testImports
const a = TextStyle(fontSize: 13);
''',
      ['TextStyle(fontSize: 13)'],
    );
  }

  Future<void> test_inside_text_widget() async {
    await assertFlagged(
      '''
$testImports
const a = Text('x', style: TextStyle(fontSize: 13));
''',
      ['TextStyle(fontSize: 13)'],
    );
  }

  Future<void> test_inside_default_text_style() async {
    await assertFlagged(
      '''
$testImports
const a = DefaultTextStyle(
  style: TextStyle(fontSize: 13),
  child: SizedBox(),
);
''',
      ['TextStyle(fontSize: 13)'],
    );
  }

  Future<void> test_const_keyword_is_part_of_the_report() async {
    await assertFlagged(
      '''
$testImports
final a = const TextStyle(fontSize: 13);
''',
      ['const TextStyle(fontSize: 13)'],
    );
  }

  Future<void> test_token_reference_is_allowed() async {
    await assertNoDiagnostics('''
$testImports
const a = AppTypography.bodyMedium;
final b = AppTypography.bodyMedium.copyWith(color: Colors.black);
''');
  }

  Future<void> test_design_system_path_is_exempt() async {
    final path = '$testPackageRootPath/lib/design_system/extra.dart';
    newFile(path, '''
import 'package:flutter/material.dart';
const a = TextStyle(fontSize: 13);
''');
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_no_config_is_silent() async {
    deleteConfig();
    await assertNoDiagnostics('''
$testImports
const a = TextStyle(fontSize: 13);
''');
  }

  Future<void> test_ignore_comment() async {
    await assertNoDiagnostics('''
$testImports
// ignore: avoid_inline_text_style
const a = TextStyle(fontSize: 13);
''');
  }
}

@reflectiveTest
class AvoidInlineTextStyleFixTest extends DtlFixTest {
  @override
  RuleId get ruleId => RuleId.avoidInlineTextStyle;

  static const _exact = 'design_token_lints.fix.avoid_inline_text_style';

  Future<void> test_exact_match() async {
    await assertFix(
      '''
$testImports
const a = TextStyle(fontSize: 12, fontWeight: FontWeight.w400);
''',
      '''
$testImports
const a = AppTypography.caption;
''',
      kindId: _exact,
    );
  }

  Future<void>
  test_exact_match_ignores_argument_order_and_weight_alias() async {
    await assertFix(
      '''
$testImports
const a = TextStyle(fontWeight: FontWeight.normal, fontSize: 12);
''',
      '''
$testImports
const a = AppTypography.caption;
''',
      kindId: _exact,
    );
  }

  Future<void> test_match_with_height() async {
    await assertFix(
      '''
$testImports
const a = TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 1.4);
''',
      '''
$testImports
const a = AppTypography.bodyMedium;
''',
      kindId: _exact,
    );
  }

  Future<void> test_const_keyword_is_replaced_too() async {
    await assertFix(
      '''
$testImports
final a = const TextStyle(fontSize: 22, fontWeight: FontWeight.bold);
''',
      '''
$testImports
final a = AppTypography.titleLarge;
''',
      kindId: _exact,
    );
  }

  Future<void> test_inside_text_widget() async {
    await assertFix(
      '''
$testImports
final a = Text('x', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400));
''',
      '''
$testImports
final a = Text('x', style: AppTypography.caption);
''',
      kindId: _exact,
    );
  }

  Future<void> test_only_color_differs_uses_copy_with() async {
    await assertFix(
      '''
$testImports
final a = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w400,
  color: Colors.red,
);
''',
      '''
$testImports
final a = AppTypography.caption.copyWith(color: Colors.red);
''',
      kindId: _exact,
    );
  }

  Future<void> test_copy_with_is_not_offered_in_const_context() async {
    await assertNoFix('''
$testImports
const a = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w400,
  color: Colors.red,
);
''');
  }

  Future<void> test_missing_height_has_no_fix() async {
    await assertNoFix('''
$testImports
const a = TextStyle(fontSize: 14, fontWeight: FontWeight.w400);
''');
  }

  Future<void> test_different_height_has_no_fix() async {
    await assertNoFix('''
$testImports
const a = TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 1.5);
''');
  }

  Future<void> test_missing_font_weight_has_no_fix() async {
    await assertNoFix('''
$testImports
const a = TextStyle(fontSize: 12);
''');
  }

  Future<void> test_unrecognised_argument_has_no_fix() async {
    await assertNoFix('''
$testImports
const a = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w400,
  fontFamily: 'Mono',
);
''');
  }

  Future<void> test_no_matching_token_has_no_fix() async {
    await assertNoFix('''
$testImports
const a = TextStyle(fontSize: 13, fontWeight: FontWeight.w400);
''');
  }

  Future<void> test_import_is_added() async {
    await assertFix(
      '''
import 'package:flutter/material.dart';
const a = TextStyle(fontSize: 12, fontWeight: FontWeight.w400);
''',
      '''
import 'package:flutter/material.dart';
import 'package:test/design_system/app_typography.dart';
const a = AppTypography.caption;
''',
      kindId: _exact,
    );
  }
}
