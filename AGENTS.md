# Repository Guidelines

## Project Structure & Module Organization

Hi Hysteria is a Bash-based installer and management utility for Hysteria2. Authoritative implementation modules live in `server/src/` and are concatenated in filename order into the distributable `server/hy2.sh`. Do not edit that generated file directly. Bootstrap logic is in `server/install.sh`; repository utilities are under `scripts/`. Translation catalogs live in `server/i18n/`, localized documentation in `md/{en,fa,ru}/`, and README variants at the repository root. Images used by documentation belong in `imgs/`. Shell integration tests are named `server/test_*.sh`.

## Build, Test, and Development Commands

- `bash scripts/build.sh` rebuilds `server/hy2.sh`, validates Bash syntax, and runs ShellCheck error checks when available.
- `bash server/test_build.sh` verifies the generated script exactly matches `server/src/`.
- `for test in server/test_*.sh; do bash "$test" || exit 1; done` runs the complete test suite.
- `bash scripts/i18n-validate.sh` checks translation key parity and `printf` placeholder counts.
- `bash -n server/src/*.sh server/install.sh scripts/*.sh` performs a quick syntax check.

Some client-config tests require `yq`; a local executable at `.devtools/yq` is detected automatically.

## Coding Style & Naming Conventions

Use Bash with four-space indentation, quoted expansions, and `snake_case` for local variables and functions. Existing shared state commonly uses the `HIHY_` prefix; preserve that convention. Prefer `set -euo pipefail` for standalone scripts and keep functions grouped in the appropriately numbered module (for example, lifecycle functions in `65-lifecycle.sh`). Run `shellcheck -S error` on changed shell files. Translation keys use lowercase `snake_case`; keep every locale synchronized with `en.json`.

## Testing Guidelines

Tests are self-contained Bash scripts using temporary fixtures and explicit `PASS`/`FAIL` assertions. Add regression coverage to the closest existing `test_*.sh`, or create a descriptively named test such as `test_install_recovery.sh`. Tests must avoid root-only operations, real service changes, and persistent host files. Rebuild before testing whenever modules change.

## Commit & Pull Request Guidelines

History follows Conventional Commit-style subjects such as `feat:`, `fix:`, `docs:`, `chore:`, and scoped forms like `fix(i18n):`. Write imperative, focused subjects and separate unrelated changes. Pull requests should explain behavior changes, list commands run, link relevant issues, and include terminal output or screenshots for menu/UI changes. Commit both source-module changes and the rebuilt `server/hy2.sh`; include matching documentation and translations when user-facing text changes.
