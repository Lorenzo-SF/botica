# Botica — Architectural Reference

> Diagnostics, health checks, feature flags, and auto-repair for Elixir — v2.1.0

---

## 1. What is Botica

Botica is the **diagnostic and feature-flag library** of the Lorenzo-SF
ecosystem. It provides two independent subsystems:

1. **Doctor** — A health-check and auto-repair engine. Run predefined checks
   (PostgreSQL, Redis, memory, disk), get a pass/fail/warning summary, and
   optionally auto-fix failures.
2. **Flags** — A feature-flag system with ETS-backed O(1) reads, GenServer-
   serialized writes, percentage rollouts, and auto-generated documentation.

---

## 2. Architecture Overview

```
┌──────────────────────────────────────────────────────────────┐
│                    Botica (Facade)                            │
│  lib/botica.ex — run, fix, health_check, flags API          │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────────┐  ┌─────────────────────────┐  │
│  │        Doctor            │  │        Flags             │  │
│  │                          │  │                          │  │
│  │  run checks in parallel  │  │  ETS-backed O(1) reads  │  │
│  │  auto-repair failures    │  │  GenServer-serialized    │  │
│  │  health_summary          │  │  writes                  │  │
│  │  validate config         │  │  percentage rollouts     │  │
│  │                          │  │  auto-doc generation     │  │
│  └──────────┬───────────────┘  └──────────┬──────────────┘ │
│             │                              │                 │
│  ┌──────────▼──────────────────┐  ┌───────▼──────────────┐  │
│  │       Runner subsystem     │  │     Store subsystem  │  │
│  │                            │  │                      │  │
│  │  Sequencer (sort/filter)   │  │  Flag struct         │  │
│  │  Executor (parallel +time) │  │  ETS Store GenServer │  │
│  │  Fixer (repair loop)       │  │  Config (defaults)   │  │
│  └────────────────────────────┘  │  Doc (FLAGS.md gen)  │  │
│                                  └──────────────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              Batteries (predefined checks)            │  │
│  │                                                      │  │
│  │  PostgreSQL  Redis  Memory  Disk                     │  │
│  │  Each: check function + fix function                 │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              Check Behaviour                          │  │
│  │                                                      │  │
│  │  Botica.Check.Behaviour — @callback with __using__   │  │
│  │  Defines: run/1, fix/1, description/0, priority/0   │  │
│  │  Custom checks implement this behaviour              │  │
│  └──────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

---

## 3. Subsystems

### 3.1 Doctor (Botica.Doctor)
- `run/1` — Run all checks in parallel (via `Botica.Runner.Executor`),
  return `{:ok, [result]}`
- `run/2` — Run with options (`:timeout`, `:stop_on_first_error`)
- `fix/1` — Run fixes for failed checks (via `Botica.Repair.Fixer`),
  return `{:ok, fix_report}`
- `health_check/1` — Quick pass/fail status map
- `batteries/0` — List available predefined checks
- `validate/1` — Validate config map structure

### 3.2 Runner
- **Sequencer** (`Botica.Runner.Sequencer`): Sort and filter checks by
  priority, tags, fixability. Group by tags.
- **Executor** (`Botica.Runner.Executor`): Parallel execution engine.
  Per-check timeout via `Task.async_stream`. `stop_on_first_error` mode.
- **Fixer** (`Botica.Repair.Fixer`): Iterates failed checks, applies fix
  functions, produces fix report (what was fixed, what failed to fix).

### 3.3 Check Behaviour (Botica.Check.Behaviour)
- `@callback run/1` — run the check
- `@callback fix/1` — attempt repair
- `@callback description/0` — human-readable description
- `@callback priority/0` — sort order
- `__using__` macro provides default implementations and result construction

### 3.4 Batteries (predefined checks)
| Check | Detection | Fix |
|-------|-----------|-----|
| PostgreSQL | `pg_isready` or TCP port 5432 probe | `systemctl start postgresql` |
| Redis | `redis-cli PING` or TCP port 6379 probe | `systemctl start redis` |
| Memory | `/proc/meminfo` or `vm_stat` | (warning only) |
| Disk | `df -k` with configurable thresholds | (warning only) |

### 3.5 Results (Botica.Check.Result)
- `build/3` — construct result from check + status + detail
- `summarize/1` — aggregate results into health summary
- `health_status/1` — derive overall status (pass/fail/warning)
- `from_exception/2` — wrap crash as failed check
- `from_timeout/2` — wrap timeout as failed check

### 3.6 Flags (Botica.Flags)
- `define/2` — Define a new flag with name, default, description, optional rollout
- `enable/1`, `disable/1` — Force state
- `set/2` — Update flag attributes
- `delete/1` — Remove a flag
- `enabled?/1` — Check if enabled (O(1), ETS direct read)
- `enabled?/2` — Check with entity rollout (`for: user`)
- `get/1` — Get full flag struct
- `all/0` — List all flags
- `count/0` — Flag count

### 3.7 Flag Internals
- **Flag struct**: name, enabled, default, description, rollout, timestamps
- **Store** (GenServer): ETS-backed (`:set`, `:public`, `read_concurrency: true`).
  O(1) reads bypass GenServer; writes are serialized to avoid races.
- **Config**: Reads flag defaults from `:botica` application env (`:flags` key) at boot.
- **Doc**: Generates `docs/FLAGS.md` markdown table from registered flags.

### 3.8 Validation (Botica.Validation)
- Shared helpers: check config is a map, has `app_name`, has `checks` list

### 3.9 Types (Botica.Types)
- Type definitions: `result`, `summary`, `config`, `check_def`, `fix_report`

---

## 4. Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| **Apero** | path: ../apero | OS detection (`Apero.OS.type/0`) |
| **Arrea** | path: ../arrea | Command execution (`Arrea.Command`) |
| **Trebejo** | path: ../trebejo | Network probing (`Trebejo.Network`), command runner (`Trebejo.Util`) |

Botica depends on the full stack: **Apero** (OS detection), **Arrea**
(command execution), **Trebejo** (network probes).

---

## 5. Consumed by

| Project | What it uses |
|---------|--------------|
| **Delfos** | `Botica.Doctor.run/1` for health diagnostics, `Botica.Doctor.fix/1` for auto-repair, `Botica.Flags` for feature flags |

Delfos uses Botica's Doctor in the `delfos doctor` command for all
self-diagnosis checks and auto-fix capabilities.

---

## 6. Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **ETS for flag reads** | O(1) reads with no GenServer round-trip. Hot path (every flag check) is maximally fast. |
| **GenServer for flag writes** | Serialized writes prevent race conditions on flag state transitions. |
| **Percentage rollouts via phash2** | Deterministic per-entity bucketing (stable across restarts). `:erlang.phash2/2` for consistent assignment. |
| **Check as behaviour** | Third-party checks implement `Botica.Check.Behaviour`. Batteries are just pre-packaged implementations. |
| **Parallel check execution** | Independent checks run concurrently via `Task.async_stream`. Configurable per-check timeout prevents one slow check from blocking others. |
| **Batteries pattern** | Common infrastructure checks (PG, Redis, memory, disk) ship with Botica. Apps add domain-specific checks via the behaviour. |
| **Auto-generated FLAGS.md** | Flag documentation never goes stale. `Botica.Flags.Doc.generate/0` writes the current state. |

---

## 7. Application Startup

```
Botica.Application.start/2
  └── Supervisor
        └── Botica.Flags.Store (GenServer)
              └── ETS table (:botica_flags)
```

The Flags Store starts at boot. Doctor is stateless — checks are defined
at compile time via config or at runtime via the behaviour.

---

## 8. Current State (v2.1.0 — Jul 2026)

- 19 source modules across 2 main subsystems (Doctor + Flags)
- 7 test files
- 4 batteries: PostgreSQL, Redis, Memory, Disk
- Check behaviour ready for custom checks
- Feature flags with O(1) reads, percentage rollouts, auto-doc generation
- Used by Delfos for `delfos doctor` command
