# design_token_lints

[![pub package](https://img.shields.io/pub/v/design_token_lints.svg)](https://pub.dev/packages/design_token_lints)
[![pub points](https://img.shields.io/pub/points/design_token_lints)](https://pub.dev/packages/design_token_lints/score)
[![CI](https://github.com/AshitaNema/design_token_lints/actions/workflows/ci.yml/badge.svg)](https://github.com/AshitaNema/design_token_lints/actions/workflows/ci.yml)
[![coverage](https://codecov.io/gh/AshitaNema/design_token_lints/branch/main/graph/badge.svg)](https://codecov.io/gh/AshitaNema/design_token_lints)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/AshitaNema/design_token_lints/blob/main/LICENSE)

Lint rules for your Flutter design system, built on Dart's official analyzer
plugin system.

- **Flag** raw colors, magic spacing, hand-written radii, text styles and
  shadows, and raw widgets that have a design-system replacement, in your IDE
  and in `dart analyze`.
- **Fix** each one with a quick fix that inserts the matching token from your
  own classes (`AppColors.primary`, `AppSpacing.md`) and adds the import.
- **Measure** how much of your UI uses the design system with
  `design_token_lints coverage`, and fail CI below a threshold.

![Quick fix replacing a raw color with a token](https://raw.githubusercontent.com/AshitaNema/design_token_lints/main/doc/quick_fix.gif)

Watch: [quick fixes in VS Code](https://github.com/AshitaNema/design_token_lints/blob/main/doc/quick_fix.mp4) ·
[coverage from 43% to 90% in the terminal](https://github.com/AshitaNema/design_token_lints/blob/main/doc/demo.mp4)

**Contents:** [Getting started](#getting-started) ·
[Example app](#example-app) · [What it reports](#what-it-reports) ·
[Configuration](#configuration) · [Rules](#rules) · [Fix everything](#fix-everything) ·
[Coverage](#coverage) ·
[Limitations](#limitations) · [How this compares](#how-this-compares) ·
[Roadmap](#roadmap)

## Getting started

**Requirements:** Dart 3.11 or later (`dart --version`).

1. Tell the analyzer to load the plugin, in the `analysis_options.yaml` at the
   root of your package (or workspace):

   ```yaml
   plugins:
     design_token_lints: ^0.1.2
   ```

2. Describe your design system. Add this to the same file, or to a
   `design_token_lints.yaml` next to `pubspec.yaml`:

   ```yaml
   design_token_lints:
     design_system:
       paths: [lib/design_system/**]
     tokens:
       color:   { class: AppColors,  file: lib/design_system/app_colors.dart }
       spacing: { class: AppSpacing, file: lib/design_system/app_spacing.dart }
   ```

3. Restart the Dart analysis server (in VS Code: *Dart: Restart Analysis
   Server*). Raw values in your code are now reported, with quick fixes.

Nothing is reported for a category until you configure its tokens, so you can
adopt one category at a time.

> **Note:** on the command line and in CI, run `dart analyze`.
> `flutter analyze` does not show analyzer plugin diagnostics, so with it the
> plugin looks like it is doing nothing.

Install the plugin only through `analysis_options.yaml`, never as a dependency in
`pubspec.yaml`. The analysis server resolves plugins in its own package, so
adding it to `pubspec.yaml` would only add its analyzer constraint to your app.

## Example app

The [example app](https://github.com/AshitaNema/design_token_lints/tree/main/example) is a small shop with a design system
in `lib/design_system/` and two versions of the same checkout screen:

- [`legacy_checkout.dart`](https://github.com/AshitaNema/design_token_lints/blob/main/example/lib/screens/legacy_checkout.dart)
  is written with raw values and reports 23 issues;
- [`checkout.dart`](https://github.com/AshitaNema/design_token_lints/blob/main/example/lib/screens/checkout.dart) uses the
  tokens and components and reports none.

Open the example in your IDE to try the quick fixes, or run
`design_token_lints coverage` in it.

## What it reports

| Rule | Severity | Flags |
| --- | --- | --- |
| [`avoid_raw_color`](#avoid_raw_color) | warning | `Color(0xFF…)`, `Color.fromARGB/fromRGBO/from`, `Colors.*` |
| [`avoid_magic_spacing`](#avoid_magic_spacing) | warning | numeric literals in `EdgeInsets`, `SizedBox`, `Gap` |
| [`avoid_raw_radius`](#avoid_raw_radius) | warning | `BorderRadius.circular(8)`, `Radius.circular(8)` |
| [`avoid_inline_text_style`](#avoid_inline_text_style) | warning | `TextStyle(...)` written by hand |
| [`avoid_raw_shadow`](#avoid_raw_shadow) | info | `BoxShadow(...)` and lists of them |
| [`prefer_design_system_component`](#prefer_design_system_component) | warning | raw widgets that have a replacement |

All rules are on by default. Every rule skips the design-system files, the
token files themselves, generated files, and anything you exclude.

To turn a rule off or change its severity, give the plugin entry a `version`
and a `diagnostics` section:

```yaml
plugins:
  design_token_lints:
    version: ^0.1.2
    diagnostics:
      avoid_raw_shadow: false
      avoid_magic_spacing: error
```

To silence one report:

```dart
// ignore: design_token_lints/avoid_raw_color
const legacyBlue = Color(0xFF123456);
```

`// ignore_for_file: design_token_lints/<rule>` silences a rule for a file.

## Configuration

The plugin framework has no per-rule options yet, so the plugin reads its own
configuration. It looks for, in this order:

1. `design_token_lints.yaml` next to `pubspec.yaml`, or
2. a top-level `design_token_lints:` section in `analysis_options.yaml` at the
   package root.

If both exist, the standalone file wins; they are not merged. The top-level
section is **not** inherited through `include:`, because it is read from the
package's own `analysis_options.yaml` only. In a pub workspace, a member
package without its own configuration uses the one at the workspace root.

The configuration is found from the package that contains the analyzed file,
cached per package, and reloaded when the configuration or a token file
changes. A malformed configuration never crashes the analyzer: the plugin
reports nothing, and `design_token_lints check-config` prints what is wrong.

```yaml
design_token_lints:
  # Files where raw values legitimately live. Globs are relative to the
  # directory that holds the configuration. The token files themselves are
  # always exempt.
  design_system:
    paths: [lib/design_system/**, lib/theme/**]
    packages: [acme_design_system]   # exempt by package name (workspaces)

  # Your existing token classes. A token is a `static const` member; no
  # annotations or code generation. `file` is a path relative to the
  # configuration, or a package: URI for tokens in a dependency.
  tokens:
    color:      { class: AppColors,     file: lib/design_system/app_colors.dart }
    spacing:    { class: AppSpacing,    file: lib/design_system/app_spacing.dart }
    radius:     { class: AppRadius,     file: lib/design_system/app_radius.dart }
    typography: { class: AppTypography, file: lib/design_system/app_typography.dart }
    shadow:     { class: AppShadows,    file: package:acme_design_system/shadows.dart }

  # Values that are always fine.
  allow:
    color: [Colors.transparent, 0xFF000000]   # Colors.<name> or an ARGB value
    spacing: [0, 2]                           # 0 is always allowed
    radius: [999]

  # When to offer "nearest token" fixes. 0 (the default) means exact only.
  matching:
    spacing_tolerance: 0     # logical pixels
    radius_tolerance: 0      # logical pixels
    color_delta_e: 2.0       # CIEDE2000; around 2 is "barely noticeable"

  # Raw widgets and what replaces them.
  components:
    ElevatedButton: { replacement: AppButton, import: package:acme_ui/acme_ui.dart }
    Text:           { replacement: AppText,   import: package:acme_ui/acme_ui.dart }

  # Files no rule applies to. Generated files (`*.g.dart`, `*.freezed.dart`,
  # and files with a "GENERATED CODE" header) are skipped without listing them.
  exclude: ["**/*.g.dart", "**/*.freezed.dart", "test/**"]

  # Exclusions for a single rule.
  rules:
    avoid_magic_spacing: { exclude: [lib/legacy/**] }
```

### How tokens are found

Each configured token file is parsed, without resolution and without a build
step, and every `static const` member of the configured class is evaluated
statically. These forms are understood:

- numbers, including arithmetic and references to other constants in the same
  class or file (`static const lg = md * 1.5;`);
- `Color(0xAARRGGBB)`, `Color.fromARGB`, `Color.fromRGBO`, `Color.from`, and
  `Colors.*`;
- `Radius.circular`, `BorderRadius.circular`, `BorderRadius.all(Radius.circular(…))`;
- `TextStyle(fontSize:, fontWeight:, height:, letterSpacing:)`;
- `BoxShadow(...)` and lists of them, with `Offset(dx, dy)`.

Members that cannot be evaluated (computed values, `static final`, getters) are
skipped. `design_token_lints check-config` lists them.

## Rules

### avoid_raw_color

Flags `Color(0xFF…)`, `Color.fromARGB`, `Color.fromRGBO`, `Color.from`, and
`Colors.<name>`, including `Colors.red.shade100` and `Colors.red[100]`, unless
allow-listed. `Colors` must be Flutter's class; your own `Colors` is ignored.
Allowed: `AppColors.primary`, `Theme.of(context).colorScheme.primary`.

```dart
// Bad
Container(color: const Color(0xFF1E88E5))

// Good
Container(color: AppColors.primary)
```

**Fix.** An exact ARGB match offers *Replace with AppColors.primary*. When a
token has the same value as another (an alias), both are offered. With
`matching.color_delta_e` set, close colors also offer *Replace with nearest
token AppColors.primary (ΔE 1.3)*, at lower priority, up to three candidates.
A color with a different alpha is never a nearest match.

A translucent color whose red, green and blue equal an opaque token, such as
`Color(0x801E88E5)`, offers *Replace with
AppColors.primary.withValues(alpha: 0.5)*. The alpha is written with two
decimals, or three when two would change the 8-bit value (`0x7F` becomes
`0.498`), so the color stays the same. This fix is not offered where a method
call is not allowed: in a constant context (`const` variables and collections)
or in a parameter's default value.

### avoid_magic_spacing

Flags numeric literals in `EdgeInsets.all/symmetric/only/fromLTRB`,
`EdgeInsetsDirectional.*`, `SizedBox(width:, height:)`, `SizedBox.square`, and
`Gap` / `SliverGap`. `0`, values in `allow.spacing`, negative numbers and
non-literal expressions are ignored.

```dart
// Bad
Padding(padding: const EdgeInsets.all(16))

// Good
Padding(padding: const EdgeInsets.all(AppSpacing.md))
```

**Fix.** *Replace 16 with AppSpacing.md.* Within `matching.spacing_tolerance`,
*Replace 15 with nearest token AppSpacing.md (Δ1)*. Tokens at the same distance
are all offered.

### avoid_raw_radius

Flags `BorderRadius.circular(n)`, `BorderRadius.all(Radius.circular(n))`,
`Radius.circular(n)`, and each corner of `BorderRadius.only/vertical/horizontal`.

```dart
// Bad
BorderRadius.circular(8)

// Good
BorderRadius.circular(AppRadius.md)   // a double token
AppRadius.card                        // a BorderRadius token
```

**Fix.** The surrounding constructor is kept when the token is a `double`, and
the whole expression is replaced when the token is a `Radius` or
`BorderRadius`. Nearest matches use `matching.radius_tolerance`.

### avoid_inline_text_style

Flags `TextStyle(...)` written outside the design system, including inside
`Text(style:)` and `DefaultTextStyle`. Allowed: `AppTypography.body`,
`Theme.of(context).textTheme.bodyMedium`, and `.copyWith(color: …)` on a token.

```dart
// Bad
Text('Total', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))

// Good
Text('Total', style: AppTypography.title)
```

**Fix.** Offered only when `fontSize` and `fontWeight` (and `height` and
`letterSpacing`, which must agree in both directions) exactly match one token.
If the style also sets `color`, the fix is
`AppTypography.title.copyWith(color: …)`, except in a `const` context, where no
fix is offered. Any other argument (`fontFamily`, `decoration`, …) means no fix.

### avoid_raw_shadow

Severity: **info**. Flags `BoxShadow(...)` and `List<BoxShadow>` literals. A list
is reported once, not per element.

```dart
// Bad
BoxDecoration(boxShadow: [BoxShadow(color: Color(0x1A000000), blurRadius: 8)])

// Good
BoxDecoration(boxShadow: AppShadows.card)
```

**Fix.** Only on an exact structural match with a shadow token (same layers,
colors, blur, spread and offset).

### prefer_design_system_component

Flags construction of a Flutter widget listed under `components:`. The widget is
matched through its resolved element, so your own `Text` class is never
reported.

```dart
// Bad
ElevatedButton(onPressed: save, child: Text('Save'))

// Good
AppButton(onPressed: save, child: AppText('Save'))
```

**Fix.** *Replace ElevatedButton with AppButton*: the class name is renamed, the
constructor name and the arguments are kept, and the configured `import` is
added (or reused, including an existing prefixed import). The fix only renames;
making the arguments compatible with the replacement is up to you.

## Fix everything

The IDE applies quick fixes one at a time. To apply every exact fix in a
project at once, use the command line tool:

```sh
dart pub global activate design_token_lints
design_token_lints fix --dry-run   # list what would change
design_token_lints fix             # apply it
```

```text
lib/screens/legacy_checkout.dart
  12:37  16 -> AppSpacing.md
  15:16  const Color(0xFFFAFAFA) -> AppColors.surface
  51:11  ElevatedButton -> AppButton
  ...

Fixed 16 issues in 1 file. Run "dart format" if any line got too long.

7 issues have no exact token; "dart analyze" lists them.
```

It runs the same detectors as the plugin and adds imports the same way. It
applies only fixes with exactly one exact token:

- **Nearest matches are never applied.** Turning `15` into `AppSpacing.md`
  changes the design, so it is left to a person in the IDE.
- **Two tokens with the same value** are listed, not fixed, so you choose.
- **A fix inside another fix** (a color inside a shadow that matches a shadow
  token) is listed; run the command again.
- `// ignore:` and `// ignore_for_file:` comments are honored.

```text
design_token_lints fix [path] [--dry-run] [--rule avoid_raw_color,avoid_magic_spacing]
```

`--dry-run` changes nothing and exits with code `1` when there is something to
fix, so CI can require that exact fixes are applied. `--rule` limits the fix to
some rules.

## Coverage

```sh
dart pub global activate design_token_lints
design_token_lints coverage
```

```text
Design system coverage: 42% (colors 25%, spacing 42%, radius 33%, typography 50%, shadows 50%, components 50%) — 7 magic spacing values in 1 file
```

Coverage of a category is `token uses / (token uses + raw values)`. A token use
is a reference to a static member of a configured token class (or a use of a
configured replacement widget); a raw value is what the rules above report. The
overall figure weights every use and every raw value equally. It runs the same
detectors as the plugin, so the numbers match what the IDE shows.

Install the command line tool globally, not as a dev dependency. A dev
dependency would add the analyzer's version constraints to your project.

```text
design_token_lints coverage [path] [--format console|json|markdown]
                            [--output file] [--fail-under 80]
                            [--category color,spacing,radius,typography,shadow,component]
design_token_lints fix [path] [--dry-run] [--rule rule,...]
design_token_lints check-config [path]
```

| Option | Meaning |
| --- | --- |
| `--format` | `console` (default), `json` (with `"schemaVersion": 1`), or `markdown` |
| `--output` | write the report to a file; a one-line summary goes to the console |
| `--fail-under N` | exit with code 1 if overall coverage is below N percent |
| `--category` | measure only these categories |

Exit codes: `0` success, `1` coverage below `--fail-under`, `2` usage or
configuration error. `check-config` validates the configuration and prints
every token it found and every member it skipped.

The JSON report has `totals`, per-`categories` statistics, per-`rules` counts,
and `files` with each finding's `line`, `column`, `rule`, `message` and
`suggestedToken`.

### In CI

This GitHub Actions job keeps one "sticky" comment on each pull request up to
date, and fails the build below 80%:

```yaml
name: Design system coverage
on: pull_request

permissions:
  contents: read
  pull-requests: write

jobs:
  coverage:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
      - run: flutter pub get
      - run: dart pub global activate design_token_lints
      - name: Measure coverage
        id: coverage
        run: |
          set +e
          design_token_lints coverage --format markdown --output coverage.md --fail-under 80
          echo "status=$?" >> "$GITHUB_OUTPUT"
      - uses: marocchino/sticky-pull-request-comment@v2
        with:
          header: design-token-lints
          path: coverage.md
      - name: Enforce the threshold
        if: steps.coverage.outputs.status != '0'
        run: exit ${{ steps.coverage.outputs.status }}
```

Run the plugin's diagnostics in CI with `dart analyze`:

```yaml
- run: dart analyze
```

## Limitations

- **Restart the analysis server** after you edit the `plugins:` section of
  `analysis_options.yaml`. Changes to the `design_token_lints` configuration and
  to token files need no restart: they are picked up the next time a file is
  analyzed, so touch (or reopen) a file to see them.
- **Plugins are configured at the root only.** Declare the plugin in the
  `analysis_options.yaml` at the package or workspace root; the analyzer ignores
  plugin declarations in nested options files.
- **The `design_token_lints:` section is not inherited through `include:`.** Put
  it in the package's own `analysis_options.yaml`, or use
  `design_token_lints.yaml`.
- **Use `dart analyze`, not `flutter analyze`, in CI.** `flutter analyze` does
  not report this plugin's diagnostics.
- **Workspaces.** The plugin keeps a small configuration and token cache for each
  configuration root. In a large workspace, give packages that share a design
  system one configuration at the workspace root rather than one each.
- **Names are matched, not resolved, for constructors.** `EdgeInsets`,
  `SizedBox`, `Gap`, `BorderRadius`, `Radius`, `TextStyle`, `BoxShadow` and
  `Color` are recognized by name, so a class of your own with one of those
  names and constructor shapes is treated the same way. `Colors` and the
  classes under `components:` are checked through the resolved element.
- **Tokens must be constant.** `static final` members, getters and values that
  need runtime evaluation (`ThemeExtension` tokens) are not read.
- **No `dart fix`.** The analysis server does not apply plugin fixes in bulk,
  so `dart fix` ignores them. Use [`design_token_lints fix`](#fix-everything)
  instead.

## How this compares

Compared with tools that also target design tokens or banned usages, as each
project documents itself (November 2026):

| | design_token_lints | [house_rules](https://pub.dev/packages/house_rules) | [design_system_lints](https://pub.dev/packages/design_system_lints) | [DCM](https://dcm.dev) `banned-usage` |
| --- | --- | --- | --- | --- |
| Runs in | IDE and `dart analyze` (analyzer plugin) | Command line and editor hook | IDE (Sidecar plugin) | IDE and command line |
| Analysis | Parsed code, plus resolved elements for `Colors` and components | Parsed code and source text; no resolved types | Not documented | Not documented |
| Token source | Your existing `static const` classes | String-keyed token maps and a palette class | Classes annotated with `@designSystem` | None: you list banned names |
| Fix to your token | Exact and nearest matches, import added | Suggestions only ("did you mean") | "Code edits", not described | Not documented |
| Coverage metric | Yes, with a CI threshold | Not documented; a baseline of finding counts | Not documented | Not documented |
| Price, latest release | Free (MIT), 2026 | Free (MIT), 2026 | Free (MIT), 2023 | Paid plans |

General rule sets such as [many_lints](https://pub.dev/packages/many_lints),
[altive_lints](https://pub.dev/packages/altive_lints) and
[clean_code_lints](https://pub.dev/packages/clean_code_lints) cover different
ground and run side by side with this plugin in `analysis_options.yaml`.

## Roadmap

- **More token sources:** `ThemeExtension` tokens, and importing tokens from
  Figma, Tokens Studio and the W3C Design Tokens format.
- **More categories:** icon sizes, elevation, and opacity (`withValues`).
- **Gradual adoption:** a baseline file that accepts existing findings, so only
  new raw values are reported.
- **CI output:** SARIF from the coverage command.
- **Plugin platform:** per-rule options in `analysis_options.yaml` once the SDK
  supports them ([dart-lang/sdk#63098](https://github.com/dart-lang/sdk/issues/63098)),
  and `dart fix` support once plugin fixes allow it.

Suggestions are welcome in the [issue tracker](https://github.com/AshitaNema/design_token_lints/issues).

## Acknowledgements

Pat O'Brien's [design_system_lints](https://pub.dev/packages/design_system_lints)
first showed that a design system can be linted. Thanks to the Dart team for the
analyzer plugin system this package is built on.

Licensed under the [MIT License](https://github.com/AshitaNema/design_token_lints/blob/main/LICENSE).
