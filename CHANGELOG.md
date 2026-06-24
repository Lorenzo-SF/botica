# Changelog

All notable changes to Botica are documented in this file.

## [0.2.0] — 2026-06-24

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
