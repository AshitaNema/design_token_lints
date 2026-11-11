# Contributing

## Setup

```sh
git clone https://github.com/AshitaNema/design_token_lints.git
cd design_token_lints
dart pub get
```

The package is pure Dart. Flutter is only needed for `example/`.

## Running the checks

```sh
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
```

Rule tests build a fake `flutter` package in memory, so they run without a
Flutter SDK. The golden files for the `coverage` and `check-config` output live
in `test/fixtures/golden/`; after an intentional change to the output run

```sh
UPDATE_GOLDENS=1 dart test test/cli_test.dart
```

and review the diff.

To check the end-to-end behavior in a real analysis server:

```sh
cd example
flutter pub get
dart analyze
```

The legacy checkout screen should be reported by every rule; the clean one
should not.

### Supported analyzer versions

`pubspec.yaml` allows `analysis_server_plugin` 0.3.15 to 0.3.26. Each plugin
release pins one analyzer release, so the range is also a range of analyzers.
CI tests the lowest and the latest resolution. To try a specific pair locally,
pin `analysis_server_plugin`, `analyzer`, `analyzer_plugin` and
`analyzer_testing` to matching versions in a scratch checkout and run
`dart analyze` and `dart test`.

## Adding a rule

1. **Detector**: add `lib/src/detectors/<name>_detector.dart`. A detector is a
   pure function of the syntax tree and the project configuration. It declares
   the node kinds it needs and reports `Finding`s, with suggestions computed up
   front. Register it in `Detectors.forRule`.
2. **Rule**: add the `RuleId` (code and category) and its `LintCode` in
   `design_token_rule.dart`. The rule class is generic; nothing else is needed.
3. **Fix**: `TokenFix` turns the suggestions of any detector into quick fixes.
   Add the rule to `RuleId.offersNearestFixes` if it can suggest near matches.
4. **Tests**: one file per rule in `test/`, covering flagged, allowed,
   exempt-path, generated-file, allow-list, no-config and ignore-comment cases,
   plus a fix test for every kind of replacement.
5. **Docs**: the README rule section and `CHANGELOG.md`.

## Releasing

1. Update the version in `pubspec.yaml` and the entry in `CHANGELOG.md`.
2. Merge to `main` once CI is green.
3. Tag the commit `vX.Y.Z` and push the tag. The `Publish` workflow publishes
   it to pub.dev with GitHub OIDC.

### One-time pub.dev setup

The first version has to be published by hand (`dart pub publish` from a
machine signed in to pub.dev), because automated publishing can only be enabled
on an existing package. Then:

1. Open <https://pub.dev/packages/design_token_lints/admin>.
2. **Publisher**: move the package to the verified publisher `ashitanema.dev`.
3. **Automated publishing** → **Enable publishing from GitHub Actions**.
4. **Repository**: `AshitaNema/design_token_lints`.
5. **Tag pattern**: `v{{version}}`.
6. Leave **Require GitHub Actions environment** off, or enter an environment
   name and add the same `environment:` to the `publish` job.
7. Save, and check that **Disable automated publishing** is not selected.
