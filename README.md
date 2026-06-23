# Botica

Environment diagnostics and health checks for Elixir. Define checks and run diagnostics with structured results.

## Installation

```elixir
def deps do
  [
    {:botica, "~> 1.0"}
  ]
end
```

## Dependencies

Botica requires:
- `:apero` - System utilities (included automatically via path in dev)
- `:arrea` - Parallel execution (included automatically via path in dev)

## Usage

### Define a health check configuration

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
    },
    %{
      id: :elixir_version,
      name: "Elixir Version",
      description: "Check Elixir version is recent enough",
      priority: 2,
      check: fn ->
        version = System.version()
        if Version.match?(version, ">= 1.15.0") do
          {:ok, "Elixir #{version}"}
        else
          {:warning, "Elixir #{version} is old"}
        end
      end,
      fix: fn -> :skipped end,
      fix_command: nil
    }
  ]
}
```

### Run diagnostics

```elixir
# Run all checks in parallel
{:ok, results} = Botica.Doctor.run(config)

# Check results
Enum.each(results, fn result ->
  IO.puts("#{result.name}: #{result.status} - #{result.message}")
end)

# Get summary
summary = Botica.Doctor.summary(results)
IO.puts("Passed: #{summary.ok}, Failed: #{summary.error}")
```

### Run automatic fixes

```elixir
# Run fixes for all failed checks
Botica.Doctor.fix(config)
```

### Quick health check

```elixir
# Returns a simple status map
result = Botica.Doctor.health_check(config)
# => %{status: :ok, summary: %{ok: 3, warning: 1, error: 0, total: 4, passed?: true}}

case result.status do
  :ok -> IO.puts("All systems healthy")
  :degraded -> IO.puts("Some checks warned")
  :fail -> IO.puts("Critical failures detected")
end
```

## Common Check Examples

### PostgreSQL

```elixir
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
```

### Redis

```elixir
%{
  id: :redis,
  name: "Redis",
  description: "Cache server is running",
  priority: 2,
  check: fn ->
    case System.cmd("redis-cli", ["ping"], stderr_to_stdout: true) do
      {"PONG\n", 0} -> {:ok, "Redis is responding"}
      {output, _} -> {:error, "Redis not responding: #{output}"}
    end
  end,
  fix: fn -> {:ok, "sudo systemctl start redis"} end,
  fix_command: "sudo systemctl start redis"
}
```

### Directory Permissions

```elixir
%{
  id: :data_dir,
  name: "Data Directory",
  description: "Application data directory is writable",
  priority: 3,
  check: fn ->
    path = "/var/data/myapp"
    if File.exists?(path) && File.stat!(path).access == :write do
      {:ok, "Data directory is writable"}
    else
      {:error, "Data directory not writable: #{path}"}
    end
  end,
  fix: fn -> {:ok, "sudo chown -R myapp:myapp /var/data/myapp"} end,
  fix_command: "sudo chown -R myapp:myapp /var/data/myapp"
}
```

## Result Structure

Each check result is a map with:

```elixir
%{
  id: :postgresql,          # Check identifier
  name: "PostgreSQL",       # Human-readable name
  status: :ok | :warning | :error,  # Check status
  message: "PostgreSQL is ready",   # Status message
  fix_command: "sudo systemctl start postgresql"  # Hint for fix
}
```

## Supervisor Integration

Integrate with an Elixir supervisor for application startup health checks:

```elixir
defmodule MyApp.Application do
  use Supervisor

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    config = Botica.config()  # Your health check configuration

    children = [
      # ... other children
      {Botica.HealthCheckWorker, config}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end

defmodule MyApp.HealthCheckWorker do
  use GenServer

  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  @impl true
  def init(config) do
    result = Botica.Doctor.health_check(config)

    if result.status == :fail do
      {:stop, {:shutdown, :health_check_failed}}
    else
      {:ok, config}
    end
  end
end
```

## API

- `Botica.Doctor.run/1` - Run all checks, returns `{:ok, [result]}`
- `Botica.Doctor.fix/1` - Run fixes for failed checks, returns `:ok`
- `Botica.Doctor.summary/1` - Get a summary map with counts
- `Botica.Doctor.health_check/1` - Convenience wrapper returning just pass/fail

## Check Definition

Each check in the config must have:
- `id` - Unique atom identifier
- `name` - Human-readable name
- `description` - What this check verifies
- `priority` - Order to run checks (lower = first)
- `check` - Zero-arity function returning `{:ok, msg}`, `{:warning, msg}`, or `{:error, msg}`
- `fix` - Zero-arity function to repair (returns `{:ok, msg}`, `{:error, msg}`, or `:skipped`)
- `fix_command` - Optional shell command hint for the user

---

## Project history

This library was developed as part of a larger internal toolkit and extracted
to open source in mid-2026. The single commit visible on `main` represents the
OSS cut-over point — all the features shipped in `1.0.0` were built and tested
before being made public. Subsequent releases (`1.0.1`, `1.1.0`, ...) will be
tagged normally, providing a clean public history going forward.

## License

MIT
