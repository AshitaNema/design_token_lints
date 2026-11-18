import 'package:analyzer/error/error.dart';
import 'package:design_token_lints/src/config/rule_id.dart';
import 'package:design_token_lints/src/rules/design_token_rule.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/rule_test_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(AvoidRawIconSizeTest);
    defineReflectiveTests(AvoidRawIconSizeFixTest);
  });
}

@reflectiveTest
class AvoidRawIconSizeTest extends DtlRuleTest {
  @override
  RuleId get ruleId => RuleId.avoidRawIconSize;

  void test_severity_is_warning() {
    expect(DtlCodes.avoidRawIconSize.severity, DiagnosticSeverity.WARNING);
  }

  Future<void> test_icon_widgets_and_theme() async {
    await assertFlagged(
      '''
$testImports
final a = Icon(null, size: 22);
final b = ImageIcon(null, size: 18.0);
final c = IconButton(onPressed: null, icon: SizedBox(), iconSize: 20);
final d = IconButton.filled(onPressed: null, icon: SizedBox(), iconSize: 28);
const e = IconThemeData(size: 26);
''',
      ['22', '18.0', '20', '28', '26'],
    );
  }

  Future<void> test_token_zero_negative_and_non_literals_pass() async {
    await assertNoDiagnostics('''
$testImports
final a = Icon(null, size: AppIconSize.md);
final b = Icon(null, size: 0);
final c = Icon(null, size: -4);
double s() => 3;
final d = Icon(null, size: s());
final e = Icon(null);
''');
  }

  Future<void> test_other_arguments_are_ignored() async {
    await assertNoDiagnostics('''
$testImports
final a = Icon(null, color: Color(0xFF1E88E5));
''');
  }

  Future<void> test_allow_list() async {
    writeConfig('''
$defaultConfig
allow:
  icon_size: [22]
''');
    await assertFlagged(
      '''
$testImports
final a = Icon(null, size: 22);
final b = Icon(null, size: 18);
''',
      ['18'],
    );
  }

  Future<void> test_design_system_path_is_exempt() async {
    newFile('$testPackageRootPath/lib/design_system/icons.dart', '''
$testImports
final a = Icon(null, size: 22);
''');
    await assertDiagnosticsInFile(
      '$testPackageRootPath/lib/design_system/icons.dart',
      [],
    );
  }

  Future<void> test_category_not_configured_is_silent() async {
    writeConfig('''
tokens:
  spacing: { class: AppSpacing, file: lib/design_system/app_spacing.dart }
''');
    await assertNoDiagnostics('''
$testImports
final a = Icon(null, size: 22);
''');
  }

  Future<void> test_message_names_the_token() async {
    const code =
        '''
$testImports
final a = Icon(null, size: 24);
''';
    await assertDiagnostics(code, [
      lint(
        code.indexOf('24'),
        2,
        messageContainsAll: ["Raw icon size '24'."],
        correctionContains: 'AppIconSize.md',
      ),
    ]);
  }
}

@reflectiveTest
class AvoidRawIconSizeFixTest extends DtlFixTest {
  @override
  RuleId get ruleId => RuleId.avoidRawIconSize;

  static const _exact = 'design_token_lints.fix.avoid_raw_icon_size';
  static const _nearest = 'design_token_lints.fix.avoid_raw_icon_size.nearest';

  Future<void> test_exact_match() async {
    final code =
        '''
$testImports
final a = Icon(null, size: 24);
''';
    final fixes = await fixesFor(code);
    expect(fixes.single.kind.id, _exact);
    expect(fixes.single.change.message, 'Replace 24 with AppIconSize.md');
    expect(apply(fixes.single, code), '''
$testImports
final a = Icon(null, size: AppIconSize.md);
''');
  }

  Future<void> test_nearest_requires_tolerance() async {
    await assertNoFix('''
$testImports
final a = Icon(null, size: 22);
''');
  }

  Future<void> test_nearest_match() async {
    writeConfig('''
$defaultConfig
matching:
  icon_size_tolerance: 2
''');
    const code =
        '''
$testImports
final a = Icon(null, size: 23);
''';
    final fixes = await fixesFor(code);
    expect(fixes.map((f) => f.kind.id), [_nearest]);
    expect(
      fixes.single.change.message,
      'Replace 23 with nearest token AppIconSize.md (Δ1)',
    );
  }

  Future<void> test_import_is_added() async {
    await assertFix(
      '''
import 'package:flutter/material.dart';
final a = Icon(null, size: 16);
''',
      '''
import 'package:flutter/material.dart';
import 'package:test/design_system/app_icon_size.dart';
final a = Icon(null, size: AppIconSize.sm);
''',
      kindId: _exact,
    );
  }
}
