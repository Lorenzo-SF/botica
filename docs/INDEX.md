# Botica — Document Index

> Diagnostics, health checks, feature flags, and auto-repair for Elixir

| Document | Description |
|----------|-------------|
| [`ARCHITECTURE.md`](./ARCHITECTURE.md) | Complete design reference: subsystems (Doctor, Runner, Check Behaviour, Batteries, Flags), dependencies, key decisions |
| [`AUDIT.md`](./AUDIT.md) | Code quality audit: from_exception crash, linked Task.async, timeout message bug, TOCTOU race in flags, 68.9% coverage, top 5 fixes |
| [`README.md`](../README.md) | English README — installation, usage, API overview |
| [`docs/README.es.md`](./README.es.md) | Spanish README |
| [`CHANGELOG.md`](../CHANGELOG.md) | Version history and release notes |
| [`LICENSE.md`](../LICENSE.md) | MIT License |
| [`plan_botica.md`](./plan_botica.md) | Historical implementation plan (flags config, doc generation) |

### Ecosystem context

Botica is the **diagnostics layer** of the Lorenzo-SF ecosystem.
It depends on Apero (OS detection), Arrea (command execution), and
Trebejo (network probes). It is consumed by Delfos (doctor command).
See the [dependency graph](../docs/ARCHITECTURE.md#5-consumed-by).
