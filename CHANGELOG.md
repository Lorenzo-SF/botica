# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Executor `:stop_on_first_error` option**: halt execution at the first failing check. Takes precedence over `:continue_on_error`.
- **Executor `:continue_on_error` option now respected**: previously the option existed in the type spec but was not consulted. Now `continue_on_error: false` stops at the first error.
- 7 new tests in `test/botica/runner/executor_test.exs` covering both options.
- Deps: arrea and apero from GitHub.
- CHANGELOG.md, dialyzer_config, doc groups_for_modules in mix.exs.

### Changed
- **i18n**: documented the existing English-only public surface under Project history and linked the 1.0.0 release to hex.pm.
- `Botica.Runner.Executor.execute/2` now uses sequential short-circuit when `stop_on_first_error: true` or `continue_on_error: false` (parallel via Arrea otherwise).
- Default per-check timeout is now applied when a check has `timeout: nil` (previously `Task.await(task, nil)` raised).

### Removed
- `Botica.Application` (the Task.Supervisor was never used; Executor manages its own tasks).
- The dep on `mod: {Botica.Application, []}` in mix.exs.
- The `:apero` and `:alaja` dep placeholders (Botica is a library, not a consumer of those).

## [1.0.0] - 2026-06-10

### Added
- Initial open source release: health checks with timeout, batteries for PostgreSQL/Redis/Memory/Disk, structured results and summary.

[1.0.0]: https://hex.pm/packages/botica/1.0.0
