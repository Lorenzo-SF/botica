defmodule Botica.Flags.Persistence.Disk do
  @moduledoc """
  Disk-backed persistence adapter for feature flags.

  Flags are stored as a single JSON document (map keyed by flag name)
  written atomically via `Apero.Atomic.File`, so a crash mid-write never
  corrupts the file. Default path is `~/.botica/flags.json`; override
  with `opts: [path: ...]` in the `:flags_persistence` config.

  ## Configuration

      config :botica, :flags_persistence, [
        adapter: Botica.Flags.Persistence.Disk,
        opts: [path: "/var/lib/botica/flags.json"]
      ]
  """

  @behaviour Botica.Flags.Persistence

  # `alias Elixir.File` must come AFTER `alias Apero.Atomic.File` — the
  # last alias wins when both bind `File`.
  alias Apero.Atomic.File
  alias Elixir.File
  alias Botica.Flags.Flag
  alias Botica.Flags.Persistence

  @default_filename "flags.json"

  @impl true
  def load_all do
    with {:ok, path} <- resolve_path(),
         {:ok, contents} <- read_file(path) do
      decode(contents)
    end
  end

  @impl true
  def save_flag(%Flag{} = flag) do
    with {:ok, path} <- resolve_path(),
         {:ok, flags} <- load_all(),
         updated = Map.put(flags_map(flags), flag.name, flag),
         {:ok, json} <- encode(updated) do
      Apero.Atomic.File.write(path, json)
    end
  end

  @impl true
  def delete_flag(name) when is_atom(name) do
    with {:ok, path} <- resolve_path(),
         {:ok, flags} <- load_all(),
         updated = Map.delete(flags_map(flags), name),
         {:ok, json} <- encode(updated) do
      Apero.Atomic.File.write(path, json)
    end
  end

  # ---------------------------------------------------------------------------
  # Internal
  # ---------------------------------------------------------------------------

  # load_all/0 returns a list; internal writes need a name-keyed map.
  defp flags_map(flags) when is_list(flags) do
    Map.new(flags, &{&1.name, &1})
  end

  defp flags_map(%{} = flags), do: flags

  defp resolve_path do
    opts = Keyword.get(Application.get_env(:botica, :flags_persistence, []), :opts, [])

    case Keyword.fetch(opts, :path) do
      {:ok, path} when is_binary(path) and path != "" ->
        {:ok, path}

      _ ->
        {:ok, default_path()}
    end
  end

  defp default_path do
    base =
      case System.get_env("BOTICA_FLAGS_DIR") do
        dir when is_binary(dir) and dir != "" -> dir
        _ -> Path.join(System.user_home!(), ".botica")
      end

    Path.join(base, @default_filename)
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, contents} -> {:ok, contents}
      {:error, :enoent} -> {:ok, "{}"}
      {:error, reason} -> {:error, {:read, reason}}
    end
  end

  defp decode(contents) do
    case Jason.decode(contents) do
      {:ok, json} when is_map(json) ->
        flags =
          json
          |> Enum.map(fn {name, data} -> {String.to_atom(name), flag_from_json(name, data)} end)
          |> Map.new()

        {:ok, Map.values(flags)}

      {:ok, _other} ->
        {:error, {:malformed, "flags file root must be a JSON object"}}

      {:error, err} ->
        {:error, {:decode, Map.get(err, :message, "invalid JSON")}}
    end
  rescue
    ArgumentError -> {:error, :invalid_data}
  end

  defp flag_from_json(name, data) when is_map(data) do
    %Flag{
      name: String.to_atom(name),
      enabled: Map.get(data, "enabled", false),
      default: Map.get(data, "default", false),
      description: Map.get(data, "description"),
      rollout: rollout_from_json(Map.get(data, "rollout")),
      created_at: datetime_from_json(Map.get(data, "created_at")),
      updated_at: datetime_from_json(Map.get(data, "updated_at"))
    }
  end

  defp flag_from_json(_name, _data), do: raise(ArgumentError, "flag entry must be a JSON object")

  # Legacy: persisted rollouts may be a plain integer percentage.
  defp rollout_from_json(nil), do: nil
  defp rollout_from_json(pct) when is_integer(pct), do: pct

  defp rollout_from_json(%{"type" => type} = rollout) when is_binary(type) do
    case type do
      "percentage" -> %{type: :percentage, value: Map.get(rollout, "value", 0)}
      "user_list" -> %{type: :user_list, users: Map.get(rollout, "users", [])}
      "attribute" -> %{type: :attribute, key: Map.get(rollout, "key"), values: Map.get(rollout, "values", [])}
      _ -> raise(ArgumentError, "unknown rollout type: #{type}")
    end
  end

  defp rollout_from_json(_other), do: raise(ArgumentError, "invalid rollout entry")

  defp datetime_from_json(nil), do: DateTime.from_unix!(0)

  defp datetime_from_json(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _offset} -> dt
      {:error, _} -> DateTime.from_unix!(0)
    end
  end

  defp encode(flags) do
    json =
      flags
      |> Enum.sort_by(fn {name, _flag} -> name end)
      |> Enum.map(fn {name, flag} -> {Atom.to_string(name), flag_to_json(flag)} end)
      |> Map.new()

    {:ok, Jason.encode!(json, pretty: true)}
  end

  defp flag_to_json(%Flag{} = flag) do
    %{
      "enabled" => flag.enabled,
      "default" => flag.default,
      "description" => flag.description,
      "rollout" => rollout_to_json(flag.rollout),
      "created_at" => DateTime.to_iso8601(flag.created_at),
      "updated_at" => DateTime.to_iso8601(flag.updated_at)
    }
  end

  defp rollout_to_json(nil), do: nil
  defp rollout_to_json(pct) when is_integer(pct), do: pct

  defp rollout_to_json(%{type: :percentage, value: value}), do: %{"type" => "percentage", "value" => value}
  defp rollout_to_json(%{type: :user_list, users: users}), do: %{"type" => "user_list", "users" => users}

  defp rollout_to_json(%{type: :attribute, key: key, values: values}),
    do: %{"type" => "attribute", "key" => key, "values" => values}
end
