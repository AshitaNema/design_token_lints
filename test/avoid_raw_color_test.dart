import 'package:analyzer/error/error.dart';
import 'package:design_token_lints/src/config/rule_id.dart';
import 'package:design_token_lints/src/rules/design_token_rule.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/rule_test_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(AvoidRawColorTest);
    defineReflectiveTests(AvoidRawColorFixTest);
  });
}

@reflectiveTest
class AvoidRawColorTest extends DtlRuleTest {
  @override
  RuleId get ruleId => RuleId.avoidRawColor;

  void test_severity_is_warning() {
    expect(DtlCodes.avoidRawColor.severity, DiagnosticSeverity.WARNING);
  }

  Future<void> test_color_constructor() async {
    await assertFlagged(
      '''
$testImports
const a = Color(0xFF123456);
''',
      ['Color(0xFF123456)'],
    );
  }

  Future<void> test_from_argb_rgbo_and_from() async {
    await assertFlagged(
      '''
$testImports
const a = Color.fromARGB(255, 1, 2, 3);
const b = Color.fromRGBO(1, 2, 3, 0.5);
const c = Color.from(alpha: 1, red: 0.1, green: 0.2, blue: 0.3);
''',
      [
        'Color.fromARGB(255, 1, 2, 3)',
        'Color.fromRGBO(1, 2, 3, 0.5)',
        'Color.from(alpha: 1, red: 0.1, green: 0.2, blue: 0.3)',
      ],
    );
  }

  Future<void> test_palette_members() async {
    await assertFlagged(
      '''
$testImports
const a = Colors.red;
final b = Colors.blue.shade100;
final c = Colors.blue[200];
const d = Colors.black;
''',
      [
        'Colors.red',
        'Colors.blue.shade100',
        'Colors.blue[200]',
        'Colors.black',
      ],
    );
  }

  Future<void> test_transparent_flagged_unless_allowed() async {
    await assertFlagged(
      '''
$testImports
const a = Colors.transparent;
''',
      ['Colors.transparent'],
    );
  }

  Future<void> test_non_literal_color_is_ignored() async {
    await assertNoDiagnostics('''
$testImports
Color f(int v) => Color(v);
''');
  }

  Future<void> test_token_reference_is_allowed() async {
    await assertNoDiagnostics('''
$testImports
const a = AppColors.primary;
''');
  }

  Future<void> test_allow_list_by_name() async {
    writeConfig('''
$defaultConfig
allow:
  color: [Colors.transparent, Colors.red.shade100]
''');
    await assertFlagged(
      '''
$testImports
const a = Colors.transparent;
final b = Colors.red.shade100;
final c = Colors.red.shade200;
''',
      ['Colors.red.shade200'],
    );
  }

  Future<void> test_allow_list_by_value() async {
    writeConfig('''
$defaultConfig
allow:
  color: [0xFF000000]
''');
    await assertFlagged(
      '''
$testImports
const a = Color(0xFF000000);
const b = Colors.black;
const c = Color(0xFF000001);
''',
      ['Color(0xFF000001)'],
    );
  }

  Future<void> test_user_defined_colors_class_is_ignored() async {
    await assertNoDiagnostics('''
class Colors {
  static const int red = 1;
}
final a = Colors.red;
''');
  }

  Future<void> test_design_system_path_is_exempt() async {
    final path = '$testPackageRootPath/lib/design_system/extra.dart';
    newFile(path, '''
import 'package:flutter/material.dart';
const a = Color(0xFF123456);
''');
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_token_file_is_exempt() async {
    writeConfig(
      defaultConfig.replaceFirst('paths: [lib/design_system/**]', 'paths: []'),
    );
    await assertNoDiagnosticsInFile(
      '$testPackageRootPath/lib/design_system/app_colors.dart',
    );
  }

  Future<void> test_generated_file_by_name_is_exempt() async {
    final path = '$testPackageRootPath/lib/styles.g.dart';
    newFile(path, '''
import 'package:flutter/material.dart';
const a = Color(0xFF123456);
''');
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_generated_file_by_header_is_exempt() async {
    final path = '$testPackageRootPath/lib/styles.dart';
    newFile(path, '''
// GENERATED CODE - DO NOT MODIFY BY HAND
import 'package:flutter/material.dart';
const a = Color(0xFF123456);
''');
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_excluded_path_is_exempt() async {
    writeConfig('''
$defaultConfig
exclude: ["lib/legacy/**"]
''');
    final path = '$testPackageRootPath/lib/legacy/old.dart';
    newFile(path, '''
import 'package:flutter/material.dart';
const a = Color(0xFF123456);
''');
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_rule_specific_exclude() async {
    writeConfig('''
$defaultConfig
rules:
  avoid_raw_color: { exclude: ["lib/legacy/**"] }
''');
    final path = '$testPackageRootPath/lib/legacy/old.dart';
    newFile(path, '''
import 'package:flutter/material.dart';
const a = Color(0xFF123456);
''');
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_exempt_package_by_name() async {
    writeConfig('''
$defaultConfig
design_system:
  packages: [test]
''');
    await assertNoDiagnostics('''
$testImports
const a = Color(0xFF123456);
''');
  }

  Future<void> test_no_config_is_silent() async {
    deleteConfig();
    await assertNoDiagnostics('''
$testImports
const a = Color(0xFF123456);
''');
  }

  Future<void> test_category_not_configured_is_silent() async {
    writeConfig('''
tokens:
  spacing: { class: AppSpacing, file: lib/design_system/app_spacing.dart }
''');
    await assertNoDiagnostics('''
$testImports
const a = Color(0xFF123456);
''');
  }

  Future<void> test_malformed_config_is_silent() async {
    writeConfig('tokens: [unclosed');
    await assertNoDiagnostics('''
$testImports
const a = Color(0xFF123456);
''');
  }

  Future<void> test_missing_token_file_is_silent() async {
    writeConfig('''
tokens:
  color: { class: AppColors, file: lib/design_system/missing.dart }
''');
    await assertNoDiagnostics('''
$testImports
const a = Color(0xFF123456);
''');
  }

  Future<void> test_top_level_section_in_analysis_options() async {
    deleteConfig();
    newAnalysisOptionsYamlFile(testPackageRootPath, '''
linter:
  rules:
    - avoid_raw_color
design_token_lints:
  tokens:
    color: { class: AppColors, file: lib/design_system/app_colors.dart }
''');
    await assertFlagged(
      '''
$testImports
const a = Color(0xFF123456);
''',
      ['Color(0xFF123456)'],
    );
  }

  Future<void> test_standalone_file_wins_over_analysis_options() async {
    newAnalysisOptionsYamlFile(testPackageRootPath, '''
linter:
  rules:
    - avoid_raw_color
design_token_lints:
  tokens:
    spacing: { class: AppSpacing, file: lib/design_system/app_spacing.dart }
''');
    await assertFlagged(
      '''
$testImports
const a = Color(0xFF123456);
''',
      ['Color(0xFF123456)'],
    );
  }

  Future<void> test_config_changes_are_picked_up() async {
    await assertFlagged(
      '''
$testImports
const a = Color(0xFF123456);
''',
      ['Color(0xFF123456)'],
    );
    deleteConfig();
    await assertNoDiagnostics('''
$testImports
const a = Color(0xFF123456);
''');
  }

  Future<void> test_ignore_comment() async {
    await assertNoDiagnostics('''
$testImports
// ignore: avoid_raw_color
const a = Color(0xFF123456);
''');
  }

  Future<void> test_ignore_for_file_comment() async {
    await assertNoDiagnostics('''
// ignore_for_file: avoid_raw_color
$testImports
const a = Color(0xFF123456);
''');
  }

  Future<void> test_message_names_suggested_token() async {
    const code =
        '''
$testImports
const a = Color(0xFF1E88E5);
''';
    final offset = code.indexOf('Color(0xFF1E88E5)');
    await assertDiagnostics(code, [
      lint(
        offset,
        'Color(0xFF1E88E5)'.length,
        messageContainsAll: ["'Color(0xFF1E88E5)'"],
        correctionContains: 'AppColors.primary',
      ),
    ]);
  }

  Future<void> test_message_without_match_names_the_class() async {
    const code =
        '''
$testImports
const a = Color(0xFF123456);
''';
    final offset = code.indexOf('Color(0xFF123456)');
    await assertDiagnostics(code, [
      lint(
        offset,
        'Color(0xFF123456)'.length,
        correctionContains: 'a token from AppColors',
      ),
    ]);
  }
}

@reflectiveTest
class AvoidRawColorFixTest extends DtlFixTest {
  @override
  RuleId get ruleId => RuleId.avoidRawColor;

  static const _exact = 'design_token_lints.fix.avoid_raw_color';
  static const _nearest = 'design_token_lints.fix.avoid_raw_color.nearest';

  Future<void> test_exact_match() async {
    await assertFix(
      '''
$testImports
const a = Color(0xFF1E88E5);
''',
      '''
$testImports
const a = AppColors.primary;
''',
      kindId: _exact,
    );
  }

  Future<void> test_exact_from_argb() async {
    await assertFix(
      '''
$testImports
const a = Color.fromARGB(255, 30, 136, 229);
''',
      '''
$testImports
const a = AppColors.primary;
''',
      kindId: _exact,
    );
  }

  Future<void> test_exact_from_palette_member() async {
    await assertFix(
      '''
$testImports
const a = Colors.white;
''',
      '''
$testImports
const a = AppColors.onPrimary;
''',
      kindId: _exact,
    );
  }

  Future<void> test_exact_offers_aliases_too() async {
    final fixes = await fixesFor('''
$testImports
const a = Color(0xFF1E88E5);
''');
    expect(fixes.map((f) => f.kind.id), [_exact, '$_exact.2']);
    expect(fixes.first.change.message, 'Replace with AppColors.primary');
  }

  Future<void> test_import_is_added() async {
    await assertFix(
      '''
import 'package:flutter/material.dart';
const a = Color(0xFF1E88E5);
''',
      '''
import 'package:flutter/material.dart';
import 'package:test/design_system/app_colors.dart';
const a = AppColors.primary;
''',
      kindId: _exact,
    );
  }

  Future<void> test_no_match_has_no_fix() async {
    await assertNoFix('''
$testImports
const a = Color(0xFF123456);
''');
  }

  Future<void> test_nearest_requires_delta_e() async {
    await assertNoFix('''
$testImports
const a = Color(0xFF1E88E6);
''');
  }

  Future<void> test_nearest_match() async {
    writeConfig('''
$defaultConfig
matching:
  color_delta_e: 2.0
''');
    const code =
        '''
$testImports
const a = Color(0xFF1E88E6);
''';
    final fixes = await fixesFor(code);
    // `alias` has the same value as `primary`, so the tie offers both.
    expect(fixes.map((f) => f.kind.id), [_nearest, '$_nearest.2']);
    expect(
      fixes.first.change.message,
      startsWith('Replace with nearest token AppColors.primary (ΔE 0'),
    );
    expect(apply(fixes.first, code), '''
$testImports
const a = AppColors.primary;
''');
  }

  Future<void> test_nearest_ignores_different_alpha() async {
    writeConfig('''
$defaultConfig
matching:
  color_delta_e: 50
''');
    await assertNoFix('''
$testImports
const a = Color(0x801E88E5);
''');
  }

  Future<void> test_exact_has_priority_over_nearest() async {
    writeConfig('''
$defaultConfig
matching:
  color_delta_e: 30
''');
    final fixes = await fixesFor('''
$testImports
const a = Color(0xFF1E88E5);
''');
    expect(fixes.first.kind.id, _exact);
    expect(fixes.first.kind.priority, greaterThan(fixes.last.kind.priority));
  }

  Future<void> test_up_to_three_nearest_candidates() async {
    writeConfig('''
$defaultConfig
matching:
  color_delta_e: 100
''');
    final fixes = await fixesFor('''
$testImports
const a = Color(0xFF1E88F0);
''');
    expect(fixes.map((f) => f.kind.id), [
      _nearest,
      '$_nearest.2',
      '$_nearest.3',
    ]);
  }
}
