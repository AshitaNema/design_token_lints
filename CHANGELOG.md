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
