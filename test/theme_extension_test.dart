import 'package:design_token_lints/src/config/rule_id.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/rule_test_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ThemeExtensionRuleTest);
    defineReflectiveTests(ThemeExtensionFixTest);
  });
}

const _palette = '''
import 'package:flutter/material.dart';

class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({required this.brand, required this.surface});
  final Color brand;
  final Color surface;

  static const light = AppPalette(
    brand: Color(0xFF1E88E5),
    surface: Color(0xFFFAFAFA),
  );
}
''';

const _imports = '''
import 'package:flutter/material.dart';
import 'package:test/design_system/app_palette.dart';
''';

String _config({String? access}) =>
    '''
design_system:
  paths: [lib/design_system/**]
tokens:
  color:
    class: AppPalette
    file: lib/design_system/app_palette.dart
    instance: light
${access == null ? '' : '    access: "$access"'}
''';

@reflectiveTest
class ThemeExtensionRuleTest extends DtlRuleTest {
  @override
  RuleId get ruleId => RuleId.avoidRawColor;

  @override
  void setUp() {
    super.setUp();
    newFile(
      '$testPackageRootPath/lib/design_system/app_palette.dart',
      _palette,
    );
    writeConfig(_config());
  }

  Future<void> test_message_shows_the_access_template() async {
    const code =
        '''
$_imports
Color f(BuildContext context) => Color(0xFF1E88E5);
''';
    await assertDiagnostics(code, [
      lint(
        code.indexOf('Color(0xFF1E88E5)'),
        'Color(0xFF1E88E5)'.length,
        correctionContains: 'Theme.of(context).extension<AppPalette>()!.brand',
      ),
    ]);
  }

  Future<void> test_the_extension_file_is_exempt() async {
    await assertNoDiagnostics('''
$_imports
Color f(AppPalette palette) => palette.brand;
''');
  }
}

@reflectiveTest
class ThemeExtensionFixTest extends DtlFixTest {
  @override
  RuleId get ruleId => RuleId.avoidRawColor;

  static const _exact = 'design_token_lints.fix.avoid_raw_color';

  @override
  void setUp() {
    super.setUp();
    newFile(
      '$testPackageRootPath/lib/design_system/app_palette.dart',
      _palette,
    );
    writeConfig(_config(access: 'context.palette.{name}'));
  }

  Future<void> test_parameter_named_context() async {
    await assertFix(
      '''
$_imports
Color f(BuildContext context) => Color(0xFF1E88E5);
''',
      '''
$_imports
Color f(BuildContext context) => context.palette.brand;
''',
      kindId: _exact,
    );
  }

  Future<void> test_default_template() async {
    writeConfig(_config());
    await assertFix(
      '''
$_imports
Color f(BuildContext context) => Color(0xFFFAFAFA);
''',
      '''
$_imports
Color f(BuildContext context) => Theme.of(context).extension<AppPalette>()!.surface;
''',
      kindId: _exact,
    );
  }

  Future<void> test_untyped_closure_parameter() async {
    await assertFix(
      '''
$_imports
final f = (context) => Color(0xFF1E88E5);
''',
      '''
$_imports
final f = (context) => context.palette.brand;
''',
      kindId: _exact,
    );
  }

  Future<void> test_state_instance_member_uses_the_getter() async {
    await assertFix(
      '''
$_imports
class Page extends StatefulWidget {
  const Page();
}

class _PageState extends State<Page> {
  Color get tint => Color(0xFF1E88E5);

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''',
      '''
$_imports
class Page extends StatefulWidget {
  const Page();
}

class _PageState extends State<Page> {
  Color get tint => context.palette.brand;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''',
      kindId: _exact,
    );
  }

  Future<void> test_no_fix_without_context() async {
    await assertNoFix('''
$_imports
final a = Color(0xFF1E88E5);
''');
  }

  Future<void> test_no_fix_with_a_context_of_another_type() async {
    await assertNoFix('''
$_imports
Color f(String context) => Color(0xFF1E88E5);
''');
  }

  Future<void> test_no_fix_in_a_static_member_of_a_state() async {
    await assertNoFix('''
$_imports
class Page extends StatefulWidget {
  const Page();
}

class _PageState extends State<Page> {
  static Color tint() => Color(0xFF1E88E5);

  @override
  Widget build(BuildContext context) => const SizedBox();
}
''');
  }

  Future<void> test_no_fix_in_a_class_that_is_not_a_state() async {
    await assertNoFix('''
$_imports
class Helper {
  Color tint() => Color(0xFF1E88E5);
}
''');
  }

  Future<void> test_no_fix_in_a_constant_context() async {
    await assertNoFix('''
$_imports
List<Color> f(BuildContext context) => const [Color(0xFF1E88E5)];
''');
  }

  Future<void>
  test_template_without_context_works_anywhere_non_constant() async {
    writeConfig(_config(access: 'AppPalette.light.{name}'));
    await assertFix(
      '''
$_imports
final a = Color(0xFF1E88E5);
''',
      '''
$_imports
final a = AppPalette.light.brand;
''',
      kindId: _exact,
    );
    await assertNoFix('''
$_imports
const a = Color(0xFF1E88E5);
''');
  }

  Future<void> test_prefixed_import_is_not_prepended_to_a_template() async {
    await assertFix(
      '''
import 'package:flutter/material.dart';
import 'package:test/design_system/app_palette.dart' as p;
Color f(BuildContext context, p.AppPalette x) => Color(0xFF1E88E5);
''',
      '''
import 'package:flutter/material.dart';
import 'package:test/design_system/app_palette.dart' as p;
Color f(BuildContext context, p.AppPalette x) => context.palette.brand;
''',
      kindId: _exact,
    );
  }
}
