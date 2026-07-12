# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **`Botica.Flags.Config`** — reads default flag definitions from
  application config (`config :botica, :flags`).
- **`Botica.Flags.Doc`** — generator that writes `docs/FLAGS.md` with
  a markdown table of all registered flags.
- **`botica:config`** — mix alias to run the doc generator.
- **`Botica.Flags.Store`** now auto-loads defaults on start and emits
  `[:botica, :flags, :put]` / `[:botica, :flags, :delete]` telemetry
  events.

## [2.0.0] - 2026-07-07

This entry consolidates everything between `1.0.0` and the current
HEAD — including the feature flags module, the production hardening
pass, the four Batteries migrations to Arrea (PostgreSQL, Redis,
Memory, Disk), the `Botica.Runner.*` / `Botica.Repair.Fixer`
additions, and the dialyzer fix in `Batteries.Redis`. Earlier
`0.x` versions are no longer maintained and have been collapsed
into this single canonical `2.0.0` entry.

### Added

- **`Botica.Flags`** — feature flags with ETS backend and deterministic
  per-entity rollouts. See `Botica.Flags` for full API.
- **`Botica.Flags.Store`** — GenServer that owns the ETS table.
- **`Botica.Flags.Flag`** — struct with timestamps + `Flag.new/2`
  factory that clamps rollout to 0..100.
- **`Botica.Application`** — new OTP application that starts the
  supervisor tree (`Botica.Flags.Store`).
- **`Botica.Doctor.flags_summary/0`** — `[:count, :flags]` snapshot.
- **`Botica.Doctor.format_flags_summary/0`** — formatted banner for
  the Doctor's diagnostic output:
  ```
  Flags (3 defined):
    ✓ beta_search     enabled  (default: true)
    ✗ new_dashboard   disabled (default: false)
    ~ rate_limiting   rollout 25% (default: false)
  ```
- 12 defdelegates on the top-level `Botica` facade.
- **`Botica.Runner.Executor`**, **`Botica.Runner.Sequencer`** —
  orchestrate and run check sequences, with `@max_default_concurrency`
  as a `Task.async_stream` cap (DoS hardening).
- **`Botica.Repair.Fixer`** — fix-step runner that pairs with each
  check's `:fix` callback.
- **`Botica.Batteries.PostgreSQL`** — health check migrated to
  Arrea (`BOTI-101`). Uses `Command.execute/2` and validates against
  empty-output edge cases.
- **`Botica.Batteries.Redis`** — health check migrated to Arrea
  (`BOTI-102`). Prefers `redis-cli` when available, falls back to
  `Apero.Network.port_open?/3` for raw TCP probes.
- **`Botica.Batteries.Memory`** — health check migrated to Arrea
  (`BOTI-103`).
- **`Botica.Batteries.Disk`** — health check migrated to Arrea
  (`BOTI-104`). Forces `LC_ALL=C` so `df` parser always sees English
  column headers regardless of host locale.

### Fixed

- **`Botica.Runner.Executor`**: was unbounded — `Task.async_stream`
  with no concurrency cap could spawn hundreds of workers on a large
  check list. Now capped at `@max_default_concurrency`.
- **`Botica.Batteries.PostgreSQL.check_connection/3`** was matching on
  empty output (`stdout == ""`) as a success case, which is impossible
  for a real `psql` invocation. Removed the impossible clause.
- **`Botica.Batteries.Redis.start_service/0`** — the `with` statement
  used `:ok <- try_start_commands()`, but `try_start_commands/0`
  always returns a 2-tuple (`{:ok, _} | {:error, _}`), never the bare
  atom `:ok`. Dialyzer flagged this as
  `pattern_match The pattern can never match the type`. The success
  branch was therefore unreachable; in the failure case the `else`
  clause caught the tuple but the runtime path was broken. Changed
  to `{:ok, _} <- try_start_commands()`. `start_service/0` now
  correctly returns `{:ok, "Redis service started"}` when the service
  was successfully started.
- **`Botica.Runner.Executor`** — removed self-referencing alias that
  broke compilation.
- **`Botica.Runner.Executor`** decoupled from Arrea (uses Alaja
  facade instead) to avoid the dep cycle.
- **`Botica.Doctor`** — Task supervisor production hardening: sudo
  permission check before systemctl calls, lower default concurrency.
- **`source_ref`** in `mix.exs` now points to the canonical `2.0.0`
  tag (was `1.0.0`). The dangling `v` prefix in the CHANGELOG footer
  was also dropped.

### CI

- Multi-stage CI: format → credo → sobelow → test+coverage → dialyzer.
- `workflow_dispatch` added for manual re-runs.
- Sobelow step dropped (Phoenix-only scanner, false positives on libs).
- Credo `--strict` relaxed to match apero/candil config.

### Tests

- 27 tests in `test/botica/flags_test.exs` covering define/enable/
  disable/set/delete, rollout bucketing (deterministic, uniform
  distribution, 0% / 100% edges, `for:` ignored when rollout is nil),
  `all/0` sorting, `count/0`, `Flag` struct (rollout clamping), and
  Doctor integration.
- 35 tests in `test/botica/batteries_test.exs` covering all four
  Batteries (PostgreSQL, Redis, Memory, Disk) — check + start_service
  paths.

## [1.0.0] - 2026-06-10

### Added
- Initial open source release: feature flags, task supervisor.

[2.0.0]: https://hex.pm/packages/botica/2.0.0
[1.0.0]: https://hex.pm/packages/botica/1.0.0


> ## A note on history
>
> The git history of this repository was rewritten as part of a
> deliberate cleanup effort. The commits you can read describe the
> codebase as it stands today — they do not preserve the original
> chronology of development.
>
> Anything worth keeping from before the rewrite was carried forward
> as tagged releases with explicit `CHANGELOG.md` entries. Anything
> not preserved is, by the maintainer's choice, no longer part of the
> canonical development line.
>
> Tag `1.0.0` points to the initial open-source cut-over; tag
> `2.0.0` points to the current HEAD and the canonical consolidated
> release. All versioned artifacts on Hex.pm and GitHub Releases
> follow this convention.