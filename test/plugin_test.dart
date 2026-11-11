import 'package:analysis_server_plugin/registry.dart';
import 'package:analyzer/error/error.dart';
import 'package:design_token_lints/main.dart';
import 'package:design_token_lints/src/config/rule_id.dart';
import 'package:design_token_lints/src/fixes/token_fix.dart';
import 'package:design_token_lints/src/plugin.dart';
import 'package:design_token_lints/src/rules/design_token_rule.dart';
import 'package:test/test.dart';

void main() {
  test('the entry point exposes the plugin', () {
    expect(plugin, isA<DesignTokenLintsPlugin>());
    expect(plugin.name, 'design_token_lints');
  });

  group('rules', () {
    final rules = [for (final id in RuleId.values) DesignTokenRule(id)];

    test('every rule id has a rule with a matching code', () {
      for (final rule in rules) {
        expect(rule.name, rule.id.code);
        expect(
          rule.diagnosticCode.lowerCaseUniqueName,
          'lintcode.${rule.id.code}',
        );
        expect(rule.diagnosticCode, DtlCodes.of(rule.id));
        expect(rule.description, isNotEmpty);
      }
    });

    test('codes are unique', () {
      final names = rules
          .map((r) => r.diagnosticCode.lowerCaseUniqueName)
          .toSet();
      expect(names.length, RuleId.values.length);
    });

    test('severities', () {
      for (final rule in rules) {
        expect(
          rule.diagnosticCode.severity,
          rule.id == RuleId.avoidRawShadow
              ? DiagnosticSeverity.INFO
              : DiagnosticSeverity.WARNING,
          reason: rule.name,
        );
      }
    });

    test('every message names the offending code and the suggestion', () {
      for (final rule in rules) {
        final code = rule.diagnosticCode;
        expect(code.correctionMessage, contains('{1}'), reason: rule.name);
      }
    });

    test('parsed results are used only by rules that need no resolution', () {
      final parsed = {
        for (final rule in rules)
          if (rule.canUseParsedResult) rule.id,
      };
      expect(parsed, {
        RuleId.avoidMagicSpacing,
        RuleId.avoidRawRadius,
        RuleId.avoidInlineTextStyle,
        RuleId.avoidRawShadow,
      });
    });
  });

  group('fixes', () {
    final registered = <(DiagnosticCode, FixGenerator)>[];

    setUpAll(
      () => registerFixes((code, generator) {
        registered.add((code, generator));
      }),
    );

    test('fix kinds are unique and follow the id scheme', () {
      final ids = <String>{};
      for (final id in RuleId.values) {
        for (final nearest in [false, true]) {
          for (var rank = 0; rank < maxNearestFixes; rank++) {
            final kind = TokenFix.kindFor(id, nearest: nearest, rank: rank);
            expect(kind.id, startsWith('design_token_lints.fix.${id.code}'));
            expect(ids.add(kind.id), isTrue, reason: kind.id);
          }
        }
      }
      expect(
        TokenFix.kindFor(RuleId.avoidRawColor, nearest: true).id,
        'design_token_lints.fix.avoid_raw_color.nearest',
      );
      expect(
        TokenFix.kindFor(RuleId.avoidRawColor, nearest: false).id,
        'design_token_lints.fix.avoid_raw_color',
      );
    });

    test('exact fixes outrank nearest fixes', () {
      final exact = TokenFix.kindFor(RuleId.avoidRawColor, nearest: false);
      final nearest = TokenFix.kindFor(RuleId.avoidRawColor, nearest: true);
      expect(exact.priority, greaterThan(nearest.priority));
    });

    test('fixes are registered for every rule', () {
      final codes = registered.map((r) => r.$1).toSet();
      expect(codes, {for (final id in RuleId.values) DtlCodes.of(id)});
    });

    test('only token rules offer nearest fixes', () {
      expect(RuleId.values.where((r) => r.offersNearestFixes), [
        RuleId.avoidRawColor,
        RuleId.avoidMagicSpacing,
        RuleId.avoidRawRadius,
      ]);
    });

    test('the plugin registers rules and fixes', () {
      final registry = _RecordingRegistry();
      DesignTokenLintsPlugin().register(registry);
      expect(registry.warningRules.length, RuleId.values.length);
      expect(registry.fixCodes.toSet().length, RuleId.values.length);
      expect(registry.lintRules, isEmpty);
    });
  });
}

class _RecordingRegistry implements PluginRegistry {
  final warningRules = <Object>[];
  final lintRules = <Object>[];
  final fixCodes = <DiagnosticCode>[];

  @override
  void registerWarningRule(Object rule) => warningRules.add(rule);

  @override
  void registerLintRule(Object rule) => lintRules.add(rule);

  @override
  void registerFixForRule(DiagnosticCode code, Object generator) =>
      fixCodes.add(code);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
