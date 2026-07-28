# Plan for `@botica` (Environment Diagnostics & Health Checks)

> **Goal** – Expand the flag registry to be configurable at runtime, generate automatic documentation for flags, and reinforce test coverage for the `Botica.Flags.Store` GenServer.

---

## 1. Preparation

| Step | Action | Outcome |
|------|--------|---------|
| 1.1 | Ensure branch `fix-tools-domains` is clean |
| 1.2 | Ensure the working tree is clean (commit any in‑progress changes before starting) |
| 1.3 | `mix deps.get` – confirm overrides for `apero`, `arrea`, `trebejo` |

## 2. Implementation

| Target | Task |
|--------|------|
| **Flag Store** | Add `Botica.Flags.Config.get/1` to read defaults from `config.exs` (runtime overrides allowed). |
| **GenServer** | Modify `Botica.Flags.Store` to auto‑load defaults on start and publish events on change.
| **Docs** | Generate a helper `Botica.Flags.Doc.generate/0` that writes `docs/FLAGS.md` including flag names, default values, and descriptions.
| **Mix Alias** | Add `botica:config` alias to run `mix botica.flags.gen` for fresh docs generation.

## 3. Tests

| Test File | Coverage Goal | Checks |
|-----------|---------------|-------|
| `test/botica/flags/store_test.exs` | 100 % | • Start/stop GenServer preserves state
| | | • Override defaults persist after restart
| `test/botica/flags/doc_test.exs` | 100 % | • Generated file has expected content

Run `mix test --cover`.

## 4. Documentation

* Add `docs/FLAGS.md` with all flag definitions.
* Update `README.md` – section “Flags” with usage examples.
* Append to `CHANGELOG.md` entry ``Added dynamic flag documentation``.

## 5. Quality

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict --format=json
mix test --cover
mix dialyzer
```

## 6. Commit & Push

```bash
git add -A
git commit -m "Extend Botica flags system with runtime config and docs"
git push origin fix-tools-domains
```

---

**End of plan for `@botica`**