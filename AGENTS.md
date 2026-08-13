# Repository Guidelines

## Project Structure & Architecture

- `src/main.luau` is the Trench Warfare entry point. It bootstraps the UI library, wires game features, and owns reload/cleanup state.
- `src/ui/Nephren.luau` is the reusable Drawing-backed UI module. Keep generic windows, controls, input handling, themes, and config persistence here; keep game-specific behavior in `main.luau`.
- `nephren.png` is the interface preview used by `README.md`.
- There is no committed test suite, package manifest, or build output. Local `.vscode/`, `tests/`, and `stylua.toml` files are ignored.

## Development & Validation Commands

The source is delivered directly; there is no compile or package step.

- `git diff --check` detects whitespace errors before a commit.
- `stylua --check src` checks formatting when StyLua and the local configuration are available.
- `stylua src` formats source files; inspect the resulting diff and avoid unrelated whole-file churn.

For behavioral validation, execute `src/main.luau` in Trench Warfare using a compatible Roblox script-executor host. The runtime must provide APIs such as `Drawing`, `loadstring`, HTTP access, and executor filesystem/debug functions. Test startup, re-execution cleanup, changed toggles, and affected UI interactions. The ignored `tests/smoke.lua` harness currently references an obsolete path and is not a passing project command.

## Coding Style & Naming

Preserve the surrounding indentation: `src/main.luau` currently uses four spaces, while the UI module uses tabs. Prefer Unix line endings, double-quoted strings, and lines no longer than 99 columns. Avoid drive-by reformatting.

Use `lowerCamelCase` for locals and private helpers, `SCREAMING_SNAKE_CASE` for constants, and `PascalCase` for class-like tables, public methods, and configuration keys. Prefix private methods and fields with `_`, for example `_syncVisibility`. Keep host API assumptions guarded with assertions or protected calls where failure is recoverable.

## Testing Guidelines

No coverage threshold or CI workflow is defined. Manually exercise the smallest affected path and include regression checks for teardown, input connections, and Drawing-object cleanup. For UI changes, verify open, close, focus, and destroy behavior. If adding automated tests, update `.gitignore`, place them under `tests/`, and document a reproducible command.

## Commits & Pull Requests

History uses short, descriptive subjects without Conventional Commit prefixes, such as `update esp` and `structure change and bootstrapper`. Prefer a specific imperative subject, for example `fix ESP cleanup on reload`, and keep each commit focused.

Pull requests should summarize behavior and affected files, list validation performed, and link an issue when applicable. Include before/after screenshots for UI, ESP, or preview-image changes. Do not commit executor-generated `Nephren.luau` or configuration files under `Nephren/configs`; scrutinize changes to download URLs and filesystem/debug hooks.
