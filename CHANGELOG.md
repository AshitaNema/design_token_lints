## Unreleased

- New rules `avoid_raw_icon_size` and `avoid_raw_elevation`, with the
  `icon_size` and `elevation` token categories, `allow.icon_size`,
  `allow.elevation`, `matching.icon_size_tolerance` and
  `matching.elevation_tolerance`. Like every rule, they report nothing until
  their tokens are configured. `fix`, `baseline` and `coverage` support them.

## 0.2.1

- Support apps that use the `material_ui` and `cupertino_ui` packages (Flutter
  3.47 and later, where `package:flutter/material.dart` is deprecated). Those
  packages declare their own `Colors` and widgets, which `avoid_raw_color` and
  `prefer_design_system_component` did not recognize, so `Colors.*` and
  configured components went unreported.
- The example app uses `material_ui`.

## 0.2.0

Adoption: easier to switch on in an existing app.

- New `design_token_lints baseline` command: records the current raw values
  in `design_token_lints.baseline.yaml`, and the plugin then reports only new
  ones. Values are matched by file, rule and code, so moving or reformatting
  code keeps them accepted. `coverage` still counts them, and reports how many
  are baselined (`baselined` in the JSON report).
- New `design_token_lints fix` command: applies every exact-token fix in a
  project at once, with imports, honoring `// ignore:` comments. Nearest
  matches and values that match two tokens are listed, not changed.
  `--dry-run` exits with code 1 when there is something to fix; `--rule`
  limits the rules.
- `avoid_raw_color`: a translucent color whose red, green and blue equal an
  opaque token now offers a fix to `Token.withValues(alpha: …)`, for example
  `Color(0x801E88E5)` to `AppColors.primary.withValues(alpha: 0.5)`. Not
  offered in constant contexts or default values, where a method call is not
  allowed.

## 0.1.2

- README: a shorter introduction, a table of contents, a getting-started
  section with requirements, a link to the example app, a comparison with
  related tools, and a grouped roadmap.
- Add a pub.dev screenshot of the quick fix.

## 0.1.1

- Fix the README on pub.dev: the demo GIF, the video links and the license
  links now use absolute URLs, so they render outside GitHub.

## 0.1.0

First release.

- Six analyzer rules, on by default once the matching tokens are configured:
  `avoid_raw_color`, `avoid_magic_spacing`, `avoid_raw_radius`,
  `avoid_inline_text_style`, `avoid_raw_shadow` and
  `prefer_design_system_component`.
- Quick fixes that replace raw values with your own tokens: exact matches,
  and "nearest" matches within the configured spacing, radius and CIEDE2000
  tolerances. The component fix swaps the widget and adds the import.
- Configuration through a `design_token_lints:` section in
  `analysis_options.yaml` or a standalone `design_token_lints.yaml`, with
  workspace-root fallback. Token values are read from your existing token
  classes; no annotations, no code generation.
- Automatic exemptions for design-system paths and packages, the token files
  themselves, and generated files.
- `design_token_lints coverage` (console, JSON, Markdown, `--fail-under`) and
  `design_token_lints check-config`.
- Works with `analysis_server_plugin` 0.3.15 to 0.3.26 (analyzer 13.0 to 14.7).

See the roadmap in the README for what comes next.
