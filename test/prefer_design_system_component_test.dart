import 'package:analyzer/error/error.dart';
import 'package:design_token_lints/src/config/rule_id.dart';
import 'package:design_token_lints/src/rules/design_token_rule.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/rule_test_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(PreferDesignSystemComponentTest);
    defineReflectiveTests(PreferDesignSystemComponentFixTest);
  });
}

@reflectiveTest
class PreferDesignSystemComponentTest extends DtlRuleTest {
  @override
  RuleId get ruleId => RuleId.preferDesignSystemComponent;

  @override
  void setUp() {
    newPackage('other_ui').addFile('lib/other_ui.dart', '''
class Text {
  const Text(String data);
}
''');
    super.setUp();
  }

  void test_severity_is_warning() {
    expect(
      DtlCodes.preferDesignSystemComponent.severity,
      DiagnosticSeverity.WARNING,
    );
  }

  Future<void> test_flags_configured_widgets_at_the_type() async {
    await assertFlagged(
      '''
$testImports
final a = ElevatedButton(onPressed: null);
final b = Text('x');
''',
      ['ElevatedButton', 'Text'],
    );
  }

  Future<void> test_named_constructor_reports_the_type_only() async {
    await assertFlagged(
      '''
$testImports
final a = ElevatedButton.icon(
  onPressed: null,
  icon: SizedBox(),
  label: SizedBox(),
);
''',
      ['ElevatedButton'],
    );
  }

  Future<void> test_unconfigured_widgets_are_allowed() async {
    await assertNoDiagnostics('''
$testImports
final a = Container();
final b = SizedBox();
''');
  }

  Future<void> test_replacement_is_allowed() async {
    await assertNoDiagnostics('''
import 'package:acme_ui/acme_ui.dart';
final a = AppButton(onPressed: null);
final b = AppText('x');
''');
  }

  Future<void> test_user_defined_class_with_the_same_name_is_ignored() async {
    await assertNoDiagnostics('''
class Text {
  const Text(String data);
}
final a = Text('x');
''');
  }

  Future<void> test_class_from_another_package_is_ignored() async {
    await assertNoDiagnostics('''
import 'package:other_ui/other_ui.dart';
final a = Text('x');
''');
  }

  Future<void> test_prefixed_flutter_import_is_still_flagged() async {
    await assertFlagged(
      '''
import 'package:flutter/material.dart' as m;
final a = m.Text('x');
''',
      ['m.Text'],
    );
  }

  Future<void> test_design_system_path_is_exempt() async {
    final path = '$testPackageRootPath/lib/design_system/app_button.dart';
    newFile(path, '''
import 'package:flutter/material.dart';
final a = ElevatedButton(onPressed: null);
''');
    await assertNoDiagnosticsInFile(path);
  }

  Future<void> test_without_components_is_silent() async {
    writeConfig('''
tokens:
  spacing: { class: AppSpacing, file: lib/design_system/app_spacing.dart }
''');
    await assertNoDiagnostics('''
$testImports
final a = ElevatedButton(onPressed: null);
''');
  }

  Future<void> test_no_config_is_silent() async {
    deleteConfig();
    await assertNoDiagnostics('''
$testImports
final a = ElevatedButton(onPressed: null);
''');
  }

  Future<void> test_ignore_comment() async {
    await assertNoDiagnostics('''
$testImports
// ignore: prefer_design_system_component
final a = ElevatedButton(onPressed: null);
''');
  }

  Future<void> test_message_names_replacement() async {
    const code =
        '''
$testImports
final a = ElevatedButton(onPressed: null);
''';
    await assertDiagnostics(code, [
      lint(
        code.indexOf('ElevatedButton'),
        'ElevatedButton'.length,
        messageContainsAll: ["'ElevatedButton'"],
        correctionContains: 'AppButton',
      ),
    ]);
  }
}

@reflectiveTest
class PreferDesignSystemComponentFixTest extends DtlFixTest {
  @override
  RuleId get ruleId => RuleId.preferDesignSystemComponent;

  static const _exact = 'design_token_lints.fix.prefer_design_system_component';

  Future<void> test_replaces_the_type_and_adds_the_import() async {
    await assertFix(
      '''
import 'package:flutter/material.dart';
final a = ElevatedButton(onPressed: null, child: SizedBox());
''',
      '''
import 'package:acme_ui/acme_ui.dart';
import 'package:flutter/material.dart';
final a = AppButton(onPressed: null, child: SizedBox());
''',
      kindId: _exact,
    );
  }

  Future<void> test_message() async {
    final fixes = await fixesFor('''
import 'package:flutter/material.dart';
final a = ElevatedButton(onPressed: null);
''');
    expect(
      fixes.single.change.message,
      'Replace ElevatedButton with AppButton',
    );
  }

  Future<void> test_named_constructor_is_kept() async {
    await assertFix(
      '''
import 'package:flutter/material.dart';
final a = ElevatedButton.icon(
  onPressed: null,
  icon: SizedBox(),
  label: SizedBox(),
);
''',
      '''
import 'package:acme_ui/acme_ui.dart';
import 'package:flutter/material.dart';
final a = AppButton.icon(
  onPressed: null,
  icon: SizedBox(),
  label: SizedBox(),
);
''',
      kindId: _exact,
    );
  }

  Future<void> test_existing_import_is_reused() async {
    await assertFix(
      '''
import 'package:flutter/material.dart';
import 'package:acme_ui/acme_ui.dart';
final a = Text('x');
''',
      '''
import 'package:flutter/material.dart';
import 'package:acme_ui/acme_ui.dart';
final a = AppText('x');
''',
      kindId: _exact,
    );
  }

  Future<void> test_existing_prefixed_import_is_honored() async {
    await assertFix(
      '''
import 'package:flutter/material.dart';
import 'package:acme_ui/acme_ui.dart' as ui;
final a = Text('x');
''',
      '''
import 'package:flutter/material.dart';
import 'package:acme_ui/acme_ui.dart' as ui;
final a = ui.AppText('x');
''',
      kindId: _exact,
    );
  }

  Future<void> test_prefixed_flutter_type_is_replaced_whole() async {
    await assertFix(
      '''
import 'package:flutter/material.dart' as m;
final a = m.Text('x');
''',
      '''
import 'package:acme_ui/acme_ui.dart';
import 'package:flutter/material.dart' as m;
final a = AppText('x');
''',
      kindId: _exact,
    );
  }

  Future<void> test_component_without_import_only_renames() async {
    writeConfig('''
components:
  Text: { replacement: AppText }
''');
    await assertFix(
      '''
import 'package:flutter/material.dart';
final a = Text('x');
''',
      '''
import 'package:flutter/material.dart';
final a = AppText('x');
''',
      kindId: _exact,
    );
  }
}
