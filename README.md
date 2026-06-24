# Botica

Environment diagnostics, health checks, and feature flags for Elixir.

[![Hex Version](https://img.shields.io/hexpm/v/botica.svg)](https://hex.pm/packages/botica)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3.svg)](https://hexdocs.pm/botica)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.md)

Botica gives you two complementary tools:

1. **`Botica.Doctor`** — define health checks, run them in parallel,
   summarise results, and optionally auto-fix failures.
2. **`Botica.Flags`** — feature flags with an ETS backend and
   deterministic per-entity rollouts. No Redis. No Postgres. Just Elixir.

## Installation

```elixir
def deps do
  [
    {:botica, "~> 1.0"}
  ]
end
```

## Usage — Health checks

```elixir
config = %{
  app_name: "myapp",
  checks: [
    %{
      id: :postgresql,
      name: "PostgreSQL",
      description: "Database server is running",
      priority: 1,
      check: fn ->
        case System.cmd("pg_isready", [], stderr_to_stdout: true) do
          {_, 0} -> {:ok, "PostgreSQL is ready"}
          {output, _} -> {:error, "PostgreSQL not ready: #{output}"}
        end
      end,
      fix: fn -> {:ok, "sudo systemctl start postgresql"} end,
      fix_command: "sudo systemctl start postgresql"
    }
  ]
}

{:ok, results} = Botica.Doctor.run(config)
summary = Botica.Doctor.summary(results)
# => %{ok: 1, warning: 0, error: 0, total: 1, passed?: true}
```

Botica also ships predefined batteries: PostgreSQL, Redis, Memory, Disk.

## Usage — Feature flags

```elixir
# Define flags (typically at boot)
Botica.Flags.define(:new_dashboard, default: false)
Botica.Flags.define(:beta_search, default: true)
Botica.Flags.define(:rate_limiting, default: false, rollout: 25)

# Query
Botica.Flags.enabled?(:new_dashboard)                       # => false
Botica.Flags.enabled?(:beta_search)                         # => true
Botica.Flags.enabled?(:rate_limiting, for: current_user.id) # => true / false deterministically

# Toggle at runtime
Botica.Flags.enable(:new_dashboard)
Botica.Flags.disable(:new_dashboard)
Botica.Flags.set(:rate_limiting, rollout: 50)

# Introspection
Botica.Flags.all()         # [%Flag{...}, ...]
Botica.Flags.get(:foo)      # {:ok, %Flag{...}} | :error
Botica.Flags.count()        # 3
```

### Flags in the Doctor banner

The Doctor also exposes a feature-flags diagnostic — useful for `botica doctor`-style
CLI banners:

```elixir
banner = Botica.Doctor.format_flags_summary()

# Flags (3 defined):
#   ✓ beta_search     enabled            (default: true)
#   ✗ new_dashboard   disabled           (default: false)
#   ~ rate_limiting   rollout 25%        (default: false)
```

## How the flags work

- **Backend**: a single ETS table (`:botica_flags`) with `:set`, `:public`,
  and `read_concurrency: true`. Reads are O(1) and lock-free.
- **Writes**: serialised through `Botica.Flags.Store` (a GenServer) so
  concurrent defines / enables / disables never race.
- **Rollout**: `:erlang.phash2/2` with range 100 — same `for:` always
  gets the same answer, even across VM restarts.
- **Zero external deps** — no Redis, no Postgres, no Mnesia.

## Configuration

`Botica.Application` starts the `Botica.Flags.Store` automatically when
you list `botica` as a dependency. You can customise the supervision tree
by overriding `mod:` in your own `mix.exs`.

## License

MIT — see [LICENSE.md](LICENSE.md).

---

**For Spanish documentation, see [README_ES.md](README_ES.md).**
