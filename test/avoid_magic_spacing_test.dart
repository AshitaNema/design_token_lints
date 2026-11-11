import 'package:analyzer/error/error.dart';
import 'package:design_token_lints/src/config/rule_id.dart';
import 'package:design_token_lints/src/rules/design_token_rule.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/rule_test_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(AvoidMagicSpacingTest);
    defineReflectiveTests(AvoidMagicSpacingFixTest);
  });
}

@reflectiveTest
class AvoidMagicSpacingTest extends DtlRuleTest {
  @override
  RuleId get ruleId => RuleId.avoidMagicSpacing;

  void test_severity_is_warning() {
    expect(DtlCodes.avoidMagicSpacing.severity, DiagnosticSeverity.WARNING);
  }

  Future<void> test_edge_insets_constructors() async {
    await assertFlagged(
      '''
$testImports
const a = EdgeInsets.all(12);
const b = EdgeInsets.symmetric(vertical: 10, horizontal: 6);
const c = EdgeInsets.only(left: 3, top: 5, right: 7, bottom: 9);
const d = EdgeInsets.fromLTRB(1, 2, 3, 4);
''',
      ['12', '10', '6', '3', '5', '7', '9', '1', '2', '3', '4'],
    );
  }

  Future<void> test_directional_edge_insets() async {
    await assertFlagged(
      '''
$testImports
const a = EdgeInsetsDirectional.all(12);
const b = EdgeInsetsDirectional.only(start: 3, end: 5);
''',
      ['12', '3', '5'],
    );
  }

  Future<void> test_sized_box() async {
    await assertFlagged(
      '''
$testImports
const a = SizedBox(width: 12, height: 20);
const b = SizedBox.square(dimension: 10);
''',
      ['12', '20', '10'],
    );
  }

  Future<void> test_gap_by_name() async {
    await assertFlagged(
      '''
class Gap {
  const Gap(double extent);
}
class SliverGap {
  const SliverGap(double extent);
}
const a = Gap(12);
const b = SliverGap(6);
''',
      ['12', '6'],
    );
  }

  Future<void> test_double_literals() async {
    await assertFlagged(
      '''
$testImports
const a = EdgeInsets.all(12.5);
''',
      ['12.5'],
    );
  }

  Future<void> test_padding_and_container() async {
    await assertFlagged(
      '''
$testImports
const a = Padding(padding: EdgeInsets.all(11));
const b = Container(margin: EdgeInsets.symmetric(horizontal: 13));
''',
      ['11', '13'],
    );
  }

  Future<void> test_zero_is_allowed() async {
    await assertNoDiagnostics('''
$testImports
const a = EdgeInsets.all(0);
const b = SizedBox(width: 0.0, height: 0);
''');
  }

  Future<void> test_negative_and_non_literal_are_ignored() async {
    await assertNoDiagnostics('''
$testImports
const a = EdgeInsets.only(left: -8);
EdgeInsets b(double v) => EdgeInsets.all(v);
const c = EdgeInsets.all(AppSpacing.md);
const d = SizedBox(width: double.infinity);
''');
  }

  Future<void> test_allow_list() async {
    writeConfig('''
$defaultConfig
allow:
  spacing: [2, 0.5]
''');
    await assertFlagged(
      '''
$testImports
const a = EdgeInsets.all(2);
const b = EdgeInsets.all(0.5);
const c = EdgeInsets.all(3);
''',
      ['3'],
    );
  }

  Future<void> test_unrelated_numbers_are_ignored() async {
    await assertNoDiagnostics('''
$testImports
const a = 16;
final b = [1, 2, 3];
''');
  }

  Future<void> test_design_system_path_is_exempt() async {
    final path = '$testPackageRootPath/lib/design_system/extra.dart';
    newFile(path, '''
import 'package:flutter/material.dart';
const a = EdgeInsets.all(12);
''');
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_generated_file_is_exempt() async {
    final path = '$testPackageRootPath/lib/layout.g.dart';
    newFile(path, '''
import 'package:flutter/material.dart';
const a = EdgeInsets.all(12);
''');
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_rule_specific_exclude() async {
    writeConfig('''
$defaultConfig
rules:
  avoid_magic_spacing: { exclude: ["lib/legacy/**"] }
''');
    final path = '$testPackageRootPath/lib/legacy/old.dart';
    newFile(path, '''
import 'package:flutter/material.dart';
const a = EdgeInsets.all(12);
''');
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_no_config_is_silent() async {
    deleteConfig();
    await assertNoDiagnostics('''
$testImports
const a = EdgeInsets.all(12);
''');
  }

  Future<void> test_category_not_configured_is_silent() async {
    writeConfig('''
tokens:
  color: { class: AppColors, file: lib/design_system/app_colors.dart }
''');
    await assertNoDiagnostics('''
$testImports
const a = EdgeInsets.all(12);
''');
  }

  Future<void> test_ignore_comment() async {
    await assertNoDiagnostics('''
$testImports
// ignore: avoid_magic_spacing
const a = EdgeInsets.all(12);
''');
  }

  Future<void> test_message_names_suggested_token() async {
    const code =
        '''
$testImports
const a = EdgeInsets.all(16);
''';
    await assertDiagnostics(code, [
      lint(
        code.indexOf('16'),
        2,
        messageContainsAll: ["'16'"],
        correctionContains: 'AppSpacing.md',
      ),
    ]);
  }
}

@reflectiveTest
class AvoidMagicSpacingFixTest extends DtlFixTest {
  @override
  RuleId get ruleId => RuleId.avoidMagicSpacing;

  static const _exact = 'design_token_lints.fix.avoid_magic_spacing';
  static const _nearest = 'design_token_lints.fix.avoid_magic_spacing.nearest';

  Future<void> test_exact() async {
    await assertFix(
      '''
$testImports
const a = EdgeInsets.all(16);
''',
      '''
$testImports
const a = EdgeInsets.all(AppSpacing.md);
''',
      kindId: _exact,
    );
  }

  Future<void> test_exact_message() async {
    final fixes = await fixesFor('''
$testImports
const a = EdgeInsets.all(16);
''');
    expect(fixes.single.change.message, 'Replace 16 with AppSpacing.md');
  }

  Future<void> test_exact_in_named_argument() async {
    await assertFix(
      '''
$testImports
const a = SizedBox(width: 24, height: 8);
''',
      '''
$testImports
const a = SizedBox(width: AppSpacing.lg, height: 8);
''',
      kindId: _exact,
    );
  }

  Future<void> test_second_diagnostic() async {
    await assertFix(
      '''
$testImports
const a = SizedBox(width: 24, height: 8);
''',
      '''
$testImports
const a = SizedBox(width: 24, height: AppSpacing.sm);
''',
      kindId: _exact,
      index: 1,
    );
  }

  Future<void> test_import_is_added() async {
    await assertFix(
      '''
import 'package:flutter/material.dart';
const a = EdgeInsets.all(16);
''',
      '''
import 'package:flutter/material.dart';
import 'package:test/design_system/app_spacing.dart';
const a = EdgeInsets.all(AppSpacing.md);
''',
      kindId: _exact,
    );
  }

  Future<void> test_no_match_has_no_fix() async {
    await assertNoFix('''
$testImports
const a = EdgeInsets.all(13);
''');
  }

  Future<void> test_tolerance_zero_has_no_nearest() async {
    await assertNoFix('''
$testImports
const a = EdgeInsets.all(15);
''');
  }

  Future<void> test_nearest_within_tolerance() async {
    writeConfig('''
$defaultConfig
matching:
  spacing_tolerance: 1
''');
    const code =
        '''
$testImports
const a = EdgeInsets.all(15);
''';
    final fixes = await fixesFor(code);
    expect(fixes.map((f) => f.kind.id), [_nearest]);
    expect(
      fixes.single.change.message,
      'Replace 15 with nearest token AppSpacing.md (Δ1)',
    );
    expect(apply(fixes.single, code), '''
$testImports
const a = EdgeInsets.all(AppSpacing.md);
''');
  }

  Future<void> test_nearest_outside_tolerance() async {
    writeConfig('''
$defaultConfig
matching:
  spacing_tolerance: 1
''');
    await assertNoFix('''
$testImports
const a = EdgeInsets.all(14);
''');
  }

  Future<void> test_equal_distance_offers_both() async {
    writeConfig('''
$defaultConfig
matching:
  spacing_tolerance: 2
''');
    final fixes = await fixesFor('''
$testImports
const a = EdgeInsets.all(6);
''');
    final texts = [for (final f in fixes) f.change.message];
    expect(texts, [
      'Replace 6 with nearest token AppSpacing.xs (Δ2)',
      'Replace 6 with nearest token AppSpacing.sm (Δ2)',
    ]);
  }

  Future<void> test_closest_candidate_comes_first() async {
    writeConfig('''
$defaultConfig
matching:
  spacing_tolerance: 4
''');
    final fixes = await fixesFor('''
$testImports
const a = EdgeInsets.all(7);
''');
    expect(fixes.first.change.message, contains('AppSpacing.sm (Δ1)'));
  }

  Future<void> test_exact_preferred_even_with_tolerance() async {
    writeConfig('''
$defaultConfig
matching:
  spacing_tolerance: 8
''');
    final fixes = await fixesFor('''
$testImports
const a = EdgeInsets.all(16);
''');
    expect(fixes.first.kind.id, _exact);
    expect(fixes.first.kind.priority, greaterThan(fixes[1].kind.priority));
  }
}
