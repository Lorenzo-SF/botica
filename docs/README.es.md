# Botica

Diagnóstico de entorno, health checks y feature flags para Elixir.

[![Versión en Hex](https://img.shields.io/hexpm/v/botica.svg)](https://hex.pm/packages/botica)
[![Documentación Hex](https://img.shields.io/badge/hex-docs-ffaff3.svg)](https://hexdocs.pm/botica)
[![Licencia](https://img.shields.io/badge/licencia-MIT-blue.svg)](LICENSE.md)

Botica te ofrece dos herramientas complementarias:

1. **`Botica.Doctor`** — define health checks, ejecútalos en paralelo,
   resume los resultados y opcionalmente auto-repara los fallos.
2. **`Botica.Flags`** — feature flags con backend ETS y rollouts
   deterministas por entidad. Sin Redis. Sin Postgres. Solo Elixir.

## Instalación

```elixir
def deps do
  [
    {:botica, "~> 1.0"}
  ]
end
```

## Uso — Health checks

```elixir
config = %{
  app_name: "myapp",
  checks: [
    %{
      id: :postgresql,
      name: "PostgreSQL",
      description: "Servidor de base de datos funcionando",
      priority: 1,
      check: fn ->
        case System.cmd("pg_isready", [], stderr_to_stdout: true) do
          {_, 0} -> {:ok, "PostgreSQL listo"}
          {output, _} -> {:error, "PostgreSQL no listo: #{output}"}
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

Botica también incluye baterías predefinidas: PostgreSQL, Redis, Memory, Disk.

## Uso — Feature flags

```elixir
# Definir flags (típicamente en el boot)
Botica.Flags.define(:new_dashboard, default: false)
Botica.Flags.define(:beta_search, default: true)
Botica.Flags.define(:rate_limiting, default: false, rollout: 25)

# Consultar
Botica.Flags.enabled?(:new_dashboard)                    # => false
Botica.Flags.enabled?(:beta_search)                      # => true
Botica.Flags.enabled?(:rate_limiting, for: usuario.id)   # => true / false determinista

# Cambiar en runtime
Botica.Flags.enable(:new_dashboard)
Botica.Flags.disable(:new_dashboard)
Botica.Flags.set(:rate_limiting, rollout: 50)

# Introspección
Botica.Flags.all()         # [%Flag{...}, ...]
Botica.Flags.get(:foo)      # {:ok, %Flag{...}} | :error
Botica.Flags.count()        # 3
```

### Flags en el banner del Doctor

El Doctor también expone un diagnóstico de feature flags — útil para
banners CLI estilo `botica doctor`:

```elixir
banner = Botica.Doctor.format_flags_summary()

# Flags (3 defined):
#   ✓ beta_search     enabled            (default: true)
#   ✗ new_dashboard   disabled           (default: false)
#   ~ rate_limiting   rollout 25%        (default: false)
```

## Cómo funcionan los flags

- **Backend**: una única tabla ETS (`:botica_flags`) con `:set`,
  `:public` y `read_concurrency: true`. Las lecturas son O(1) y sin
  bloqueo.
- **Escrituras**: serializadas vía `Botica.Flags.Store` (un GenServer)
  para que defines/enables/disables concurrentes nunca pisen.
- **Rollout**: `:erlang.phash2/2` con rango 100 — el mismo `for:` siempre
  obtiene la misma respuesta, incluso tras reiniciar la VM.
- **Cero dependencias externas** — sin Redis, sin Postgres, sin Mnesia.

## Configuración

`Botica.Application` arranca `Botica.Flags.Store` automáticamente cuando
listás `botica` como dependencia. Podés customizar el árbol de supervisión
sobreescribiendo `mod:` en tu propio `mix.exs`.

## Licencia

MIT — ver [LICENSE.md](LICENSE.md).
