# Architecture

design_token_lints is an analyzer plugin plus a command line tool. Both run the
same detectors over the same configuration, so the IDE, `dart analyze` and the
coverage report always agree.

```text
analysis_options.yaml / design_token_lints.yaml
          │   ConfigLoader: find the package, read, validate, cache
          ▼
     DtlConfig ───────► TokenIndex   (token files parsed, cached with the config)
          │                  │
          └────────┬─────────┘
                   ▼
              ProjectConfig ── exemptions (paths, packages, token files, generated)
                   │
        ┌──────────┴───────────┐
        ▼                      ▼
 DesignTokenRule          ProjectAnalyzer
 (one per rule)           (coverage command)
        │                      │
        └──────► Detector ◄────┘        pure AST → Finding + TokenSuggestion
                   │
                   ▼
        TokenFix (quick fixes)       UsageCounter → CoverageReport → renderers
```

## Layout

| Path | Responsibility |
| --- | --- |
| `lib/main.dart` | The top-level `plugin` the analysis server loads. |
| `lib/design_token_lints.dart` | The small public API: configuration model, `TokenIndex`, detectors, coverage report. |
| `lib/src/config/` | `DtlConfig` (parsing and validation), `ConfigLoader` (lookup and caching), exemptions, package discovery. |
| `lib/src/tokens/` | Static evaluation of token declarations, `TokenIndex`, `NearestTokenMatcher`, CIEDE2000, the Flutter `Colors` table. |
| `lib/src/detectors/` | One pure detector per rule, plus the visitors that feed them. |
| `lib/src/rules/` | `DesignTokenRule`, the single `AnalysisRule` implementation, and the diagnostic codes. |
| `lib/src/fixes/` | `TokenFix`, the single quick-fix producer; `BulkFixer` and `IgnoreComments` for the `fix` command. |
| `lib/src/report/` | Usage counting, `ProjectAnalyzer`, `CoverageReport`, renderers. |
| `lib/src/cli/`, `bin/` | The command line tool. |

## Configuration

`ConfigLoader.lookup(file)` finds the package that contains the file by walking
up to the nearest `pubspec.yaml`. In that directory it reads
`design_token_lints.yaml` if it exists, otherwise the `design_token_lints:`
section of `analysis_options.yaml`. The two are never merged, and the section is
read from that one file only, so it is not inherited through `include:`. A
package that is a workspace member (`resolution: workspace`) and has no
configuration of its own falls back to the workspace root.

Parsing is total: `DtlConfig.parse` never throws, and records `ConfigIssue`s
instead. A document that is not a mapping, or that is not valid YAML, yields a
configuration that is not present, so every rule stays silent. Unknown keys are
warnings; missing token files and classes are errors that disable the affected
category. The CLI prints the issues.

Results are cached per configuration directory, in an `Expando` keyed by the
`ResourceProvider`. An entry is reused while the modification stamps of the
configuration file, `analysis_options.yaml` and every token file (including ones
that do not exist yet) are unchanged. Pubspec parsing is cached by stamp as
well. Everything reads through the analyzer's `ResourceProvider`, never
`dart:io`, which is what lets the tests run on an in-memory file system.

## Token discovery

`TokenIndex.build` parses each configured token file with `parseString`, which
gives an unresolved syntax tree and needs no build step. It collects the
`static const` fields of the configured class and the file's top-level
`const`s, and evaluates every initializer with `StaticEvaluator`.

The evaluator handles numeric literals and arithmetic, references to other
constants (with cycle detection), `Color` constructors, the Flutter `Colors`
palette (a generated table, `tool/generate_material_colors.dart`), `FontWeight`,
`Radius`/`BorderRadius`, `TextStyle`, and `BoxShadow`. Constructor calls are
recognized both as `InstanceCreationExpression` and as `MethodInvocation`,
because before resolution `Color(0xFF…)` parses as a method call; `CallView`
hides the difference. A member that cannot be evaluated becomes a
`SkippedToken`.

Resolution would not help here: the files that violate the rules often do not
import the token file, so there is no element to resolve against.

`file:` accepts a path or a `package:` URI, resolved through the nearest
`.dart_tool/package_config.json`.

## Detectors

A `Detector` declares the `NodeKind`s it inspects and implements
`check(node, report)`. It produces `Finding`s, each carrying the narrowest node
to report at and a list of `TokenSuggestion`s (token, distance, replacement
range, replacement text, import). Suggestions are computed once, by the
detector, so the rule message, the quick fix and the coverage report cannot
disagree.

- Number-valued rules (spacing, radius) report at the literal, so a surrounding
  constructor is kept, and match with `NearestTokenMatcher.matchNumber`.
- Colors match on ARGB, then on CIEDE2000 in CIE L*a*b* with equal alpha. A
  translucent color with the RGB of an opaque token also gets an exact
  suggestion of `Token.withValues(alpha: …)`, unless the node is in a constant
  context or a default value. The
  implementation is tested against the reference data in Sharma, Wu and Dalal,
  *The CIEDE2000 Color-Difference Formula* (2005).
- Typography and shadows match structurally and only exactly.
- Constructors are recognized by name, so most rules need only the parsed tree.
  `Colors.*` and the classes under `components:` are checked through the
  resolved element, because identity matters there.
- Nodes inside a configured token class are ignored.

## Rules and the analysis server

Every `RuleId` has one `DesignTokenRule`, registered with
`registerWarningRule` so that it is on by default. The server calls
`registerNodeProcessors` once per library, so the rule decides there, once,
whether it has anything to do: it looks up the configuration and registers
nothing if the rule's category is not configured. Exemptions that depend on the
file (design-system paths, generated files, excludes) are checked per
compilation unit when a finding is reported, with the result cached per path.

A server only uses parsed results when every enabled rule says it can
(`canUseParsedResult`). Colors and components need resolution, so in practice
the plugin runs on resolved units; the other rules do not depend on it.

## Quick fixes

`TokenFix` is the only `ResolvedCorrectionProducer`. It finds the diagnostic's
node, re-runs the rule's detector, takes the `rank`-th exact or nearest
suggestion, and edits the file. The plugin API registers one producer per fix
kind, so ranks are separate registrations: up to two exact fixes and three
nearest ones, with ids `design_token_lints.fix.<rule>[.nearest][.<n>]`. Exact
fixes outrank nearest ones. Imports go through `importLibraryElement`, which
reuses an existing import and honors its prefix.

`design_token_lints fix` (`BulkFixer`) applies the same suggestions outside the
IDE. It walks the project with `ProjectAnalyzer.walkFiles`, keeps findings that
have exactly one exact suggestion, drops findings silenced by `// ignore:`
comments (`IgnoreComments`, which reads comment tokens with the analysis
server's line rules), and skips a replacement that overlaps a larger one. Each
file gets one `ChangeBuilder` edit, so imports are added once, and the edits
are applied with `SourceEdit.applySequence`. Files are written only after the
whole project has been analyzed without configuration errors.

## Coverage

`ProjectAnalyzer` builds an `AnalysisContextCollection` over the target
directory, so analyzer excludes apply. For each file it looks up the
configuration, skips exempt files, resolves the unit and walks it once with the
active detectors (`DetectorWalker`) and once with `UsageCounter`. A usage is a
reference to a member of a configured token class, or the construction of a
configured replacement widget. Category coverage is
`usages / (usages + findings)`; the overall figure is the same ratio over all
counts. Renderers (`console`, `json`, `markdown`) are pure functions of the
`CoverageReport`.

## Performance

- A rule whose category is not configured registers no visitors.
- Detectors are asked only about the node kinds they declare, and most reject a
  node after one name comparison.
- Configuration, token indexes and pubspecs are parsed once and revalidated with
  one stat call per file.
- Token files are parsed, not resolved.

## Supported analyzers

`pubspec.yaml` allows `analysis_server_plugin` 0.3.15 to 0.3.26 and the analyzer
releases they pin (13.0 to 14.7). Every plugin release pins one analyzer, so
the range is a range of pairs. The code uses only APIs present across the range:
for example it reads the AST through `CallView` and file-system children through
`childFile`, because `NamedArgument` and `Folder.getFile` do not exist in every
version. Analyzer 12 and older use a different argument model and are not
supported.

## Known limitations

- Constructors other than `Colors` and the components are matched by name.
- Tokens must be constant; `static final`, getters and `ThemeExtension` tokens
  are skipped.
- Plugin fixes cannot be applied in bulk by `dart fix`; the `fix` command
  covers exact fixes.
- The `Colors` table follows the Flutter version it was generated from.
