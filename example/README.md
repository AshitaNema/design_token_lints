# acme_shop

A small Flutter app that enforces its own design system with
[design_token_lints](https://github.com/AshitaNema/design_token_lints).

| Path | What it is |
| --- | --- |
| `lib/design_system/` | The design system: `AppColors`, `AppSpacing`, `AppRadius`, `AppTypography`, `AppShadows`, and the `AppButton` and `AppText` widgets. |
| `lib/screens/checkout.dart` | A screen written against the design system. It has no diagnostics. |
| `lib/screens/legacy_checkout.dart` | The same screen with every value hard-coded. Every rule reports something here. |
| `analysis_options.yaml` | Loads the plugin from the checkout (`path: ../`). |
| `design_token_lints.yaml` | Points the plugin at the token classes and components. |

## Try it

```sh
cd example
flutter pub get
dart analyze
```

Use `dart analyze`. `flutter analyze` does not report the plugin's diagnostics.
In an IDE, restart the analysis server once after `flutter pub get`, open
`lib/screens/legacy_checkout.dart`, and use the quick-fix menu on any underlined
value.

Expected `dart analyze` output:

```text
Analyzing example...

warning - lib/screens/legacy_checkout.dart:12:37 - Magic spacing value '16'. Try using AppSpacing.md. - avoid_magic_spacing
warning - lib/screens/legacy_checkout.dart:13:54 - Magic spacing value '12'. Try using a token from AppSpacing. - avoid_magic_spacing
warning - lib/screens/legacy_checkout.dart:13:68 - Magic spacing value '24'. Try using AppSpacing.lg. - avoid_magic_spacing
warning - lib/screens/legacy_checkout.dart:15:16 - Raw color 'const Color(0xFFFAFAFA)' bypasses the design system. Try using AppColors.surface. - avoid_raw_color
warning - lib/screens/legacy_checkout.dart:16:23 - Raw corner radius 'BorderRadius.circular(8)'. Try using AppRadius.md. - avoid_raw_radius
warning - lib/screens/legacy_checkout.dart:19:20 - Raw color 'Color(0x1A000000)' bypasses the design system. Try using a token from AppColors. - avoid_raw_color
warning - lib/screens/legacy_checkout.dart:28:17 - 'Text' has a design-system replacement. Try using AppText. - prefer_design_system_component
warning - lib/screens/legacy_checkout.dart:30:20 - Inline TextStyle bypasses the design system. Try using AppTypography.title. - avoid_inline_text_style
warning - lib/screens/legacy_checkout.dart:32:34 - Magic spacing value '8'. Try using AppSpacing.sm. - avoid_magic_spacing
warning - lib/screens/legacy_checkout.dart:33:11 - 'Text' has a design-system replacement. Try using AppText. - prefer_design_system_component
warning - lib/screens/legacy_checkout.dart:35:20 - Inline TextStyle bypasses the design system. Try using AppTypography.caption. - avoid_inline_text_style
warning - lib/screens/legacy_checkout.dart:38:22 - Raw color 'Colors.grey.shade600' bypasses the design system. Try using a token from AppColors. - avoid_raw_color
warning - lib/screens/legacy_checkout.dart:41:34 - Magic spacing value '15'. Try using AppSpacing.md (nearest match). - avoid_magic_spacing
warning - lib/screens/legacy_checkout.dart:43:50 - Magic spacing value '12'. Try using a token from AppSpacing. - avoid_magic_spacing
warning - lib/screens/legacy_checkout.dart:43:59 - Magic spacing value '4'. Try using AppSpacing.xs. - avoid_magic_spacing
warning - lib/screens/legacy_checkout.dart:43:69 - Magic spacing value '12'. Try using a token from AppSpacing. - avoid_magic_spacing
warning - lib/screens/legacy_checkout.dart:45:22 - Raw color 'const Color(0xFF1E88E6)' bypasses the design system. Try using AppColors.primary (nearest match). - avoid_raw_color
warning - lib/screens/legacy_checkout.dart:46:29 - Raw corner radius 'BorderRadius.circular(999)'. Try using AppRadius.pill. - avoid_raw_radius
warning - lib/screens/legacy_checkout.dart:48:26 - 'Text' has a design-system replacement. Try using AppText. - prefer_design_system_component
warning - lib/screens/legacy_checkout.dart:50:34 - Magic spacing value '24'. Try using AppSpacing.lg. - avoid_magic_spacing
warning - lib/screens/legacy_checkout.dart:51:11 - 'ElevatedButton' has a design-system replacement. Try using AppButton. - prefer_design_system_component
warning - lib/screens/legacy_checkout.dart:51:57 - 'Text' has a design-system replacement. Try using AppText. - prefer_design_system_component
   info - lib/screens/legacy_checkout.dart:17:20 - Hand-written shadow bypasses the design system. Try using AppShadows.card. - avoid_raw_shadow

23 issues found.
```

`Magic spacing value '15'` is offered the nearest token because the
configuration sets `matching.spacing_tolerance: 1`, and `0xFF1E88E6` is offered
`AppColors.primary` because `matching.color_delta_e` is `2.0`.

## Coverage

Install the command line tool, then measure the example:

```sh
dart pub global activate design_token_lints   # or: dart pub global activate --source path ..
design_token_lints coverage
```

```text
Design system coverage: 43% (colors 33%, spacing 40%, radius 33%, typography 50%, shadows 50%, components 50%) — 9 magic spacing values in 1 file

  Category     Coverage  Token uses  Raw values
  colors       33%       2           4
  spacing      40%       6           9
  radius       33%       1           2
  typography   50%       2           2
  shadows      50%       1           1
  components   50%       5           5
  overall      43%       17          23

Files with the most raw values:
  lib/screens/legacy_checkout.dart (23)

3 files checked.
```

`design_token_lints check-config` prints the tokens it found. Add
`--format markdown` or `--format json` for the other reports, and
`--fail-under 80` to fail a CI job below 80%.

## Recording the quick-fix GIF

The GIF in the main README (`doc/quick_fix.gif`) shows one quick fix being
applied. To record it:

1. Open the `example` folder in VS Code with the Dart extension. Run `flutter
   pub get` and restart the analysis server.
2. Open `lib/screens/legacy_checkout.dart` at a size of about 900×500 pixels,
   with the font at 16 pt or larger.
3. Start a screen recorder on the editor window (for example Kap on macOS,
   ScreenToGif on Windows, or Peek on Linux).
4. Place the cursor on `const Color(0xFFFAFAFA)`, press `Cmd+.` (`Ctrl+.`) and
   choose *Replace with AppColors.surface*. The import is added automatically.
5. Stop after the underline disappears. Aim for 5 to 8 seconds, 15 frames per
   second, under 1 MB.
6. Save it as `doc/quick_fix.gif` in the repository root. It is excluded from
   the published package by `.pubignore`.
