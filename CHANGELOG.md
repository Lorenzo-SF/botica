# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `Botica.Flags` — feature flags with ETS backend and deterministic
  per-entity rollouts. See `Botica.Flags` for full API.
- `Botica.Flags.Store` — GenServer that owns the ETS table.
- `Botica.Flags.Flag` — struct with timestamps + `Flag.new/2` factory
  that clamps rollout to 0..100.
- `Botica.Application` — new OTP application that starts the supervisor
  tree (`Botica.Flags.Store`).
- `Botica.Doctor.flags_summary/0` — `[:count, :flags]` snapshot.
- `Botica.Doctor.format_flags_summary/0` — formatted banner for the
  Doctor's diagnostic output:
  ```
  Flags (3 defined):
    ✓ beta_search     enabled  (default: true)
    ✗ new_dashboard   disabled (default: false)
    ~ rate_limiting   rollout 25% (default: false)
  ```
- 12 defdelegates on the top-level `Botica` facade.

### Tests

- 27 tests in `test/botica/flags_test.exs` covering define/enable/disable/
  set/delete, rollout bucketing (deterministic, uniform distribution,
  0% / 100% edges, `for:` ignored when rollout is nil), `all/0` sorting,
  `count/0`, `Flag` struct (rollout clamping), and Doctor integration.

### Notes

- Adds a new OTP application start. Existing consumers that included
  `botica` as a dependency will now start the `Botica.Flags.Store`
  GenServer automatically. Override `mod:` in your own `mix.exs` if
  you need a custom supervisor tree.

## [1.0.0] - 2026-06-10

### Added
- Initial open source release: feature flags, task supervisor.

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
> Tag `v1.0.0` points to the initial open-source cut-over.
> All versioned artifacts on Hex.pm and GitHub Releases follow this
> convention.
