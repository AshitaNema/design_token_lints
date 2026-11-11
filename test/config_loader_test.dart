import 'package:analyzer/file_system/memory_file_system.dart';
import 'package:design_token_lints/src/config/config.dart';
import 'package:design_token_lints/src/config/config_loader.dart';
import 'package:design_token_lints/src/config/exemptions.dart';
import 'package:design_token_lints/src/config/package_locator.dart';
import 'package:design_token_lints/src/config/rule_id.dart';
import 'package:test/test.dart';

const _tokens = '''
tokens:
  spacing: { class: AppSpacing, file: lib/s.dart }
''';

void main() {
  late MemoryResourceProvider provider;
  late ConfigLoader loader;

  setUp(() {
    provider = MemoryResourceProvider();
    loader = ConfigLoader();
    provider.newFile('/pkg/pubspec.yaml', 'name: app\n');
    provider.newFile(
      '/pkg/lib/s.dart',
      'abstract final class AppSpacing { static const md = 16; }',
    );
    provider.newFile('/pkg/lib/screen.dart', '');
  });

  ConfigLookup lookup([String path = '/pkg/lib/screen.dart']) =>
      loader.lookup(provider.getFile(path));

  group('lookup', () {
    test('no configuration', () {
      final result = lookup();
      expect(result.project.isActive, isFalse);
      expect(result.packageName, 'app');
    });

    test('standalone file', () {
      provider.newFile('/pkg/design_token_lints.yaml', _tokens);
      final result = lookup();
      expect(result.project.config.source, ConfigSource.standalone);
      expect(result.project.isRuleActive(RuleId.avoidMagicSpacing), isTrue);
      expect(result.project.isRuleActive(RuleId.avoidRawColor), isFalse);
      expect(result.project.index.length, 1);
    });

    test('top-level section of analysis_options.yaml', () {
      provider.newFile(
        '/pkg/analysis_options.yaml',
        'linter:\n  rules: []\ndesign_token_lints:\n${_indent(_tokens)}',
      );
      final result = lookup();
      expect(result.project.config.source, ConfigSource.analysisOptions);
      expect(result.project.isRuleActive(RuleId.avoidMagicSpacing), isTrue);
    });

    test('the standalone file wins and the two are not merged', () {
      provider.newFile(
        '/pkg/analysis_options.yaml',
        'design_token_lints:\n'
            '  tokens:\n'
            '    color: { class: AppColors, file: lib/c.dart }\n',
      );
      provider.newFile('/pkg/design_token_lints.yaml', _tokens);
      final config = lookup().project.config;
      expect(config.source, ConfigSource.standalone);
      expect(config.tokens.keys, {DesignCategory.spacing});
    });

    test('analysis_options.yaml without a section', () {
      provider.newFile('/pkg/analysis_options.yaml', 'linter:\n  rules: []\n');
      expect(lookup().project.isActive, isFalse);
    });

    test('an empty standalone file is present but enforces nothing', () {
      provider.newFile('/pkg/design_token_lints.yaml', '');
      final project = lookup().project;
      expect(project.isActive, isTrue);
      for (final rule in RuleId.values) {
        expect(project.isRuleActive(rule), isFalse);
      }
    });

    test('malformed YAML never throws', () {
      provider.newFile('/pkg/design_token_lints.yaml', 'tokens: [unclosed');
      final project = lookup().project;
      expect(project.isActive, isFalse);
      expect(project.issues.single.message, contains('not valid YAML'));
    });

    test('a configuration that is not a mapping', () {
      provider.newFile('/pkg/design_token_lints.yaml', '- a\n- b\n');
      final project = lookup().project;
      expect(project.isActive, isFalse);
      expect(project.config.hasErrors, isTrue);
    });

    test('files outside any package', () {
      provider.newFile('/loose/a.dart', '');
      final result = lookup('/loose/a.dart');
      expect(result.project.isActive, isFalse);
      expect(result.packageName, '');
    });

    test('nested directories use the nearest package', () {
      provider.newFile('/pkg/design_token_lints.yaml', _tokens);
      provider.newFile('/pkg/lib/a/b/c.dart', '');
      expect(lookup('/pkg/lib/a/b/c.dart').project.isActive, isTrue);
    });

    test('a nested package does not inherit the outer configuration', () {
      provider.newFile('/pkg/design_token_lints.yaml', _tokens);
      provider.newFile('/pkg/sub/pubspec.yaml', 'name: sub\n');
      provider.newFile('/pkg/sub/lib/a.dart', '');
      final result = lookup('/pkg/sub/lib/a.dart');
      expect(result.project.isActive, isFalse);
      expect(result.packageName, 'sub');
    });
  });

  group('caching', () {
    test('returns the same project while nothing changes', () {
      provider.newFile('/pkg/design_token_lints.yaml', _tokens);
      expect(identical(lookup().project, lookup().project), isTrue);
    });

    test('reloads when the configuration changes', () {
      provider.newFile('/pkg/design_token_lints.yaml', _tokens);
      final before = lookup().project;
      provider.modifyFile(
        '/pkg/design_token_lints.yaml',
        '$_tokens\nmatching: { spacing_tolerance: 2 }\n',
      );
      final after = lookup().project;
      expect(identical(before, after), isFalse);
      expect(after.config.spacingTolerance, 2);
    });

    test('reloads when a token file changes', () {
      provider.newFile('/pkg/design_token_lints.yaml', _tokens);
      expect(lookup().project.index.length, 1);
      provider.modifyFile(
        '/pkg/lib/s.dart',
        'abstract final class AppSpacing { static const md = 16; '
            'static const lg = 24; }',
      );
      expect(lookup().project.index.length, 2);
    });

    test('notices a token file that appears later', () {
      provider.newFile(
        '/pkg/design_token_lints.yaml',
        'tokens:\n  spacing: { class: AppSpacing, file: lib/later.dart }\n',
      );
      expect(
        lookup().project.index.hasCategory(DesignCategory.spacing),
        isFalse,
      );
      provider.newFile(
        '/pkg/lib/later.dart',
        'abstract final class AppSpacing { static const md = 16; }',
      );
      expect(
        lookup().project.index.hasCategory(DesignCategory.spacing),
        isTrue,
      );
    });

    test('notices a deleted configuration', () {
      provider.newFile('/pkg/design_token_lints.yaml', _tokens);
      expect(lookup().project.isActive, isTrue);
      provider.deleteFile('/pkg/design_token_lints.yaml');
      expect(lookup().project.isActive, isFalse);
    });

    test('notices a new configuration', () {
      expect(lookup().project.isActive, isFalse);
      provider.newFile('/pkg/design_token_lints.yaml', _tokens);
      expect(lookup().project.isActive, isTrue);
    });

    test('caches are independent per file system', () {
      final other = MemoryResourceProvider();
      other.newFile('/pkg/pubspec.yaml', 'name: app\n');
      other.newFile('/pkg/lib/screen.dart', '');
      provider.newFile('/pkg/design_token_lints.yaml', _tokens);
      expect(lookup().project.isActive, isTrue);
      expect(
        loader.lookup(other.getFile('/pkg/lib/screen.dart')).project.isActive,
        isFalse,
      );
    });
  });

  group('workspaces', () {
    setUp(() {
      provider.newFile(
        '/ws/pubspec.yaml',
        'name: ws\nworkspace:\n  - packages/app\n  - packages/ui\n',
      );
      provider.newFile(
        '/ws/packages/app/pubspec.yaml',
        'name: app\nresolution: workspace\n',
      );
      provider.newFile('/ws/packages/app/lib/a.dart', '');
      provider.newFile(
        '/ws/packages/ui/pubspec.yaml',
        'name: acme_ui\nresolution: workspace\n',
      );
      provider.newFile('/ws/packages/ui/lib/b.dart', '');
      provider.newFile(
        '/ws/packages/ui/lib/s.dart',
        'abstract final class AppSpacing { static const md = 16; }',
      );
    });

    test('a member falls back to the workspace root configuration', () {
      provider.newFile(
        '/ws/design_token_lints.yaml',
        'design_system:\n  packages: [acme_ui]\n'
            'tokens:\n  spacing: { class: AppSpacing, file: packages/ui/lib/s.dart }\n',
      );
      final result = lookup('/ws/packages/app/lib/a.dart');
      expect(result.project.config.rootPath, '/ws');
      expect(result.packageName, 'app');
      expect(result.project.isRuleActive(RuleId.avoidMagicSpacing), isTrue);
    });

    test('design_system.packages exempts a member by name', () {
      provider.newFile(
        '/ws/design_token_lints.yaml',
        'design_system:\n  packages: [acme_ui]\n'
            'tokens:\n  spacing: { class: AppSpacing, file: packages/ui/lib/s.dart }\n',
      );
      final ui = lookup('/ws/packages/ui/lib/b.dart');
      final app = lookup('/ws/packages/app/lib/a.dart');
      expect(
        ui.project.exemptionFor(
          '/ws/packages/ui/lib/b.dart',
          packageName: ui.packageName,
        ),
        Exemption.designSystemPackage,
      );
      expect(
        app.project.exemptionFor(
          '/ws/packages/app/lib/a.dart',
          packageName: app.packageName,
        ),
        isNull,
      );
    });

    test("a member's own configuration wins over the workspace root", () {
      provider.newFile('/ws/design_token_lints.yaml', _tokens);
      provider.newFile(
        '/ws/packages/app/design_token_lints.yaml',
        'tokens:\n  spacing: { class: AppSpacing, file: ../ui/lib/s.dart }\n',
      );
      final result = lookup('/ws/packages/app/lib/a.dart');
      expect(result.project.config.rootPath, '/ws/packages/app');
    });

    test('a package that is not a workspace member does not fall back', () {
      provider.newFile('/ws/design_token_lints.yaml', _tokens);
      provider.newFile('/ws/packages/other/pubspec.yaml', 'name: other\n');
      provider.newFile('/ws/packages/other/lib/a.dart', '');
      expect(lookup('/ws/packages/other/lib/a.dart').project.isActive, isFalse);
    });
  });

  group('PackageLocator', () {
    test('reads pubspec fields', () {
      final info = PackageLocator.nearest(
        provider.getFile('/pkg/lib/screen.dart'),
      )!;
      expect(info.name, 'app');
      expect(info.isWorkspaceMember, isFalse);
      expect(info.isWorkspaceRoot, isFalse);
      expect(info.root.path, '/pkg');
    });

    test('an unreadable pubspec is ignored', () {
      provider.newFile('/bad/pubspec.yaml', 'name: [unclosed');
      provider.newFile('/bad/a.dart', '');
      expect(PackageLocator.nearest(provider.getFile('/bad/a.dart')), isNull);
    });

    test('changes to the pubspec are noticed', () {
      final file = provider.getFile('/pkg/lib/screen.dart');
      expect(PackageLocator.nearest(file)!.name, 'app');
      provider.modifyFile('/pkg/pubspec.yaml', 'name: renamed\n');
      expect(PackageLocator.nearest(file)!.name, 'renamed');
      provider.deleteFile('/pkg/pubspec.yaml');
      expect(PackageLocator.nearest(file), isNull);
    });

    test('a pubspec without a name has an empty name', () {
      provider.newFile('/anon/pubspec.yaml', 'version: 1.0.0\n');
      provider.newFile('/anon/a.dart', '');
      expect(
        PackageLocator.nearest(provider.getFile('/anon/a.dart'))!.name,
        '',
      );
    });
  });
}

String _indent(String text) =>
    text.trimRight().split('\n').map((line) => '  $line').join('\n');
