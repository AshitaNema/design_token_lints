import 'package:analysis_server_plugin/edit/fix/dart_fix_context.dart';
import 'package:analysis_server_plugin/edit/fix/fix.dart';
// ignore: implementation_imports
import 'package:analysis_server_plugin/src/correction/dart_change_workspace.dart';
// ignore: implementation_imports
import 'package:analysis_server_plugin/src/correction/fix_generators.dart';
// ignore: implementation_imports
import 'package:analysis_server_plugin/src/correction/fix_processor.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/instrumentation/service.dart';
// ignore: implementation_imports
import 'package:analyzer/src/diagnostic/diagnostic.dart' as diag;
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:design_token_lints/src/config/rule_id.dart';
import 'package:design_token_lints/src/plugin.dart';
import 'package:design_token_lints/src/rules/design_token_rule.dart';
import 'package:test/test.dart';

import 'fake_flutter.dart';

/// Sources of the design-system package shared by the tests.
const acmeUiLibrary = r'''
import 'package:flutter/material.dart';

class AppButton extends Widget {
  const AppButton({required void Function()? onPressed, Widget? child});
  const AppButton.icon({
    required void Function()? onPressed,
    required Widget icon,
    required Widget label,
  });
}

class AppText extends Widget {
  const AppText(String data, {TextStyle? style});
}
''';

/// A token class for each category, in the test package.
const appColorsSource = r'''
import 'package:flutter/material.dart';

abstract final class AppColors {
  static const Color primary = Color(0xFF1E88E5);
  static const Color primaryDark = Color(0xFF1565C0);
  static const Color onPrimary = Colors.white;
  static const Color surface = Color(0xFFFAFAFA);
  static const Color scrim = Color(0x99000000);
  static const Color alias = primary;
}
''';

const appSpacingSource = r'''
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}
''';

const appRadiusSource = r'''
import 'package:flutter/material.dart';

abstract final class AppRadius {
  static const double sm = 4;
  static const double md = 8;
  static const Radius lgRadius = Radius.circular(16);
  static const BorderRadius xlBorder = BorderRadius.circular(24);
}
''';

const appTypographySource = r'''
import 'package:flutter/material.dart';

abstract final class AppTypography {
  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );
  static const TextStyle titleLarge = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.bold,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );
}
''';

const appShadowsSource = r'''
import 'package:flutter/material.dart';

abstract final class AppShadows {
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 8, offset: Offset(0, 2)),
  ];
  static const BoxShadow single = BoxShadow(
    color: Color(0x33000000),
    blurRadius: 4,
  );
}
''';

const _tokenFiles = {
  'app_colors': appColorsSource,
  'app_spacing': appSpacingSource,
  'app_radius': appRadiusSource,
  'app_typography': appTypographySource,
  'app_shadows': appShadowsSource,
};

/// The configuration used by most tests.
const defaultConfig = '''
design_system:
  paths: [lib/design_system/**]
tokens:
  color: { class: AppColors, file: lib/design_system/app_colors.dart }
  spacing: { class: AppSpacing, file: lib/design_system/app_spacing.dart }
  radius: { class: AppRadius, file: lib/design_system/app_radius.dart }
  typography: { class: AppTypography, file: lib/design_system/app_typography.dart }
  shadow: { class: AppShadows, file: lib/design_system/app_shadows.dart }
components:
  ElevatedButton: { replacement: AppButton, import: 'package:acme_ui/acme_ui.dart' }
  Text: { replacement: AppText, import: 'package:acme_ui/acme_ui.dart' }
''';

/// Imports that give test sources access to Flutter and the design system.
const testImports = '''
import 'package:flutter/material.dart';
import 'package:test/design_system/app_colors.dart';
import 'package:test/design_system/app_spacing.dart';
import 'package:test/design_system/app_radius.dart';
import 'package:test/design_system/app_typography.dart';
import 'package:test/design_system/app_shadows.dart';
''';

/// Base class for tests of one rule.
abstract class DtlRuleTest extends AnalysisRuleTest {
  /// The rule under test.
  RuleId get ruleId;

  @override
  List<DiagnosticCode> get ignoredDiagnosticCodes => [
    ...super.ignoredDiagnosticCodes,
    diag.unusedImport,
  ];

  @override
  void setUp() {
    rule = DesignTokenRule(ruleId);
    newPackage('flutter').addFile('lib/material.dart', fakeFlutterMaterial);
    newPackage('acme_ui').addFile('lib/acme_ui.dart', acmeUiLibrary);
    super.setUp();
    for (final entry in _tokenFiles.entries) {
      newFile(
        '$testPackageRootPath/lib/design_system/${entry.key}.dart',
        entry.value,
      );
    }
    writeConfig(defaultConfig);
  }

  /// Writes the standalone configuration file.
  void writeConfig(String yaml) {
    newFile('$testPackageRootPath/design_token_lints.yaml', yaml);
  }

  /// Removes every configuration, so the plugin has nothing to enforce.
  void deleteConfig() {
    deleteFile('$testPackageRootPath/design_token_lints.yaml');
  }

  /// Asserts that exactly the given [snippets] of [code] are reported, in
  /// order of appearance. A snippet may be repeated to expect several
  /// reports at successive occurrences.
  Future<void> assertFlagged(String code, List<String> snippets) async {
    final ranges = <(int, int)>[];
    var from = 0;
    for (final snippet in snippets) {
      final offset = code.indexOf(snippet, from);
      if (offset < 0) {
        fail('"$snippet" does not occur in the source after offset $from.');
      }
      ranges.add((offset, snippet.length));
      from = offset + snippet.length;
    }
    final expected = [
      for (final (offset, length) in ranges) lint(offset, length),
    ];
    await assertDiagnostics(code, expected);
  }
}

/// Base class for tests of the quick fixes of one rule.
abstract class DtlFixTest extends DtlRuleTest {
  static bool _registered = false;

  @override
  void setUp() {
    super.setUp();
    if (!_registered) {
      _registered = true;
      registerFixes(
        (code, generator) => registeredFixGenerators.registerFixForLint(
          code as LintCode,
          generator,
        ),
      );
    }
  }

  /// The file the fix tests write their source to.
  String get fixTestFilePath => '$testPackageRootPath/lib/fix_test.dart';

  /// Computes the fixes offered for the [index]-th diagnostic in [code].
  Future<List<Fix>> fixesFor(String code, {int index = 0}) async {
    newFile(fixTestFilePath, code);
    result = await resolveFile(fixTestFilePath);
    final diagnostics =
        result.diagnostics
            .where((d) => d.diagnosticCode == DtlCodes.of(ruleId))
            .toList()
          ..sort((a, b) => a.offset.compareTo(b.offset));
    expect(
      diagnostics.length,
      greaterThan(index),
      reason: 'Expected a diagnostic at index $index.',
    );
    final session = result.session;
    final library = await session.getResolvedLibrary(fixTestFilePath);
    final context = DartFixContext(
      instrumentationService: InstrumentationService.NULL_SERVICE,
      workspace: DartChangeWorkspace([session]),
      libraryResult: library as ResolvedLibraryResult,
      unitResult: result,
      error: diagnostics[index],
    );
    final fixes = await computeFixes(context);
    return fixes
        .where((f) => f.kind.id.startsWith('design_token_lints.'))
        .toList();
  }

  /// Applies [fix] to [code].
  String apply(Fix fix, String code) {
    final edit = fix.change.getFileEdit(fixTestFilePath);
    expect(edit, isNotNull, reason: 'The fix does not edit the test file.');
    return SourceEdit.applySequence(code, edit!.edits);
  }

  /// Asserts that applying the fix whose id is [kindId] to [code] produces
  /// [expected].
  Future<void> assertFix(
    String code,
    String expected, {
    required String kindId,
    int index = 0,
  }) async {
    final fixes = await fixesFor(code, index: index);
    final matching = fixes.where((f) => f.kind.id == kindId).toList();
    expect(
      matching,
      isNotEmpty,
      reason:
          'No fix "$kindId". Offered: ${fixes.map((f) => f.kind.id).toList()}',
    );
    expect(apply(matching.first, code), expected);
  }

  /// Asserts that no fix is offered for the [index]-th diagnostic.
  Future<void> assertNoFix(String code, {int index = 0}) async {
    final fixes = await fixesFor(code, index: index);
    expect(
      fixes,
      isEmpty,
      reason: 'Unexpected fixes: ${fixes.map((f) => f.kind.id)}',
    );
  }
}
