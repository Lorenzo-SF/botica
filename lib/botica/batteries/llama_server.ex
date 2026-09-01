defmodule Botica.Batteries.LlamaServer do
  @moduledoc """
  Llama-server lifecycle management — used by any project that needs
  to download, configure, launch, and health-check a `llama-server`
  process running a specific GGUF model.

  ## Capabilities

    * **Find or download the binary** — `find_binary/1` returns the
      absolute path, or downloads via `Botica.Batteries.LlamaServer.Installer`
      when missing.
    * **Build the args** — `build_args/2` produces the canonical
      `llama-server` flags for the given role + config.
    * **Spawn the process** — `start/2` and `stop/1` use
      `Arrea.LongRunning` so the process is supervised, restartable,
      and hot-swappable.
    * **Health-check** — `running?/1` probes the `/health` endpoint;
      the same function used inside `start/2` to wait for readiness.
    * **Predefined checks** — `check/1` returns a `Botica.Check`
      spec suitable for `Botica.Doctor`.

  ## Roles

  Two roles are handled side by side (chat completion vs embeddings):

    * `:chat`     — higher `--parallel`, larger `--ctx-size`,
                     reasoning-friendly args (spec-decode, cache q8).
    * `:embedding` — `--embedding`, smaller model, separate batch
                     ergonomics.

  Both call into the same generic launcher, differing only in the
  role-specific args and config block they accept.

  ## Use cases

    * `delfos` (this project's primary consumer) uses `:chat` and
      `:embedding` simultaneously via its `Delfos.LLM.Internal`
      and `Delfos.LLM.Embed` adapters, each a thin wrapper that
      delegates to this module.
    * Any other Elixir app that needs a managed local LLM can reuse
      the same module without duplicating the lifecycle plumbing.
  """

  require Logger

  alias Apero.Proc

  # Defaults per role. Keys mirror the args literally — they're
  # transformed into CLI args by `build_args/2`. The `n_gpu_layers`
  # key accepts :auto so the caller can let VRAM decide.

  @defaults_by_role %{
    chat: %{
      ctx_size: 128_072,
      n_gpu_layers: :auto,
      cache_type_k: "q8_0",
      cache_type_v: "q8_0",
      batch_size: 4096,
      ubatch_size: 1024,
      parallel: 8,
      keep: 8192,
      n_predict: 8192,
      temp: 1.0,
      top_p: 1.0,
      top_k: 0,
      reasoning_format: "auto",
      threads: 12,
      threads_batch: 24,
      prio: 2,
      slot_prompt_similarity: 0.2,
      spec_type: "ngram-mod",
      spec_ngram_mod_n_min: 8,
      spec_ngram_mod_n_max: 20,
      spec_ngram_mod_n_match: 40,
      flash_attn: "on",
      no_mmap: true,
      slot_save_path: "/tmp/llama-server-cache"
    },
    embedding: %{
      ctx_size: 8_192,
      n_gpu_layers: 0,
      cache_type_k: "q4_0",
      cache_type_v: "q4_0",
      batch_size: 1024,
      ubatch_size: 1024,
      parallel: 4,
      embedding: true,
      pooling: "last",
      embd_normalize: 2,
      threads: 12,
      threads_batch: 20,
      device: "none",
      no_kv_offload: true,
      no_op_offload: true,
      no_host: true,
      no_mmproj_offload: true,
      fit: "off",
      flash_attn: "on",
      no_mmap: true,
      slot_save_path: "/tmp/llama-server-cache-embedding"
    }
  }

  @typedoc "Role selectors."
  @type role :: :chat | :embedding

  @typedoc "Resolved config passed to `start/2`."
  @type config :: %{
          required(:gguf_path) => String.t(),
          required(:port) => pos_integer(),
          optional(:host) => String.t(),
          optional(:api_key) => String.t(),
          optional(:alias) => String.t(),
          optional(:binary) => String.t(),
          optional(:llama_server_path) => String.t(),
          optional(:hardware_plan) => %{required(:device) => :gpu | :cpu},
          optional(:extra_args) => [String.t()],
          optional(any()) => any()
        }

  @doc """
  Finds the absolute path to `llama-server`, downloading a
  precompiled binary if needed. Priority:

    1. Explicit override (`llama_server_path`).
    2. `which llama-server` in PATH (returns absolute path).
    3. Installable via `Botica.Batteries.LlamaServer.Installer`.

  ## Options

    * `:force_download` — re-download even if a binary already exists.
  """
  @spec find_binary(keyword()) :: {:ok, String.t()} | {:error, term()}
  def find_binary(opts \\ []) do
    case Keyword.fetch(opts, :llama_server_path) do
      {:ok, path} when is_binary(path) ->
        if File.exists?(path) do
          {:ok, path}
        else
          find_via_path_or_install(opts)
        end

      _ ->
        find_via_path_or_install(opts)
    end
  end

  defp find_via_path_or_install(opts) do
    case Proc.which("llama-server") do
      nil -> download_or_error(opts)
      bin -> {:ok, bin}
    end
  end

  defp download_or_error(opts) do
    if Keyword.get(opts, :force_download, false) or
         Botica.Batteries.LlamaServer.Installer.not_installed?() do
      Botica.Batteries.LlamaServer.Installer.install()
    else
      {:error, :no_llama_server}
    end
  end

  @doc """
  Builds the full arg list for `llama-server`. Merges:

    * defaults for the role (`:chat` / `:embedding`)
    * user overrides (in `config`)
    * auto-resolved device (`hardware_plan.device`) when `:auto`
    * `extra_args` (always appended last)

  Returns a list suitable to pass to `Arrea.LongRunning.start_link/1`
  or `Port.open/2`.
  """
  @spec build_args(role(), config()) :: [String.t()]
  def build_args(role, config) do
    defaults = Map.get(@defaults_by_role, role) || %{}

    # The defaults here are *low priority*: any key in `config` overrides
    # them. Crucially, we do NOT restrict `config` to default keys — the
    # caller may pass things like `:llama_server_path`, `:gguf_path`,
    # etc. that aren't in our defaults.
    merged =
      defaults
      |> Map.merge(config)
      |> maybe_apply_device(Map.get(config, :hardware_plan))

    _ =
      if not Map.has_key?(merged, :gguf_path) do
        raise ArgumentError, "Botica build_args config must include :gguf_path"
      end

    _base =
      [
        "--model",
        Map.fetch!(merged, :gguf_path),
        "--host",
        Map.get(merged, :host, "127.0.0.1"),
        "--port",
        to_string(Map.fetch!(merged, :port)),
        "--api-key",
        Map.get(merged, :api_key, "sk-local-dev-key"),
        "--alias",
        Map.get(merged, :alias, "default"),
        "--ctx-size",
        to_string(merged[:ctx_size] || 8192),
        "--n-gpu-layers",
        to_string(Map.get(merged, :n_gpu_layers, 0)),
        "--cache-type-k",
        to_string(merged[:cache_type_k] || "q8_0"),
        "--cache-type-v",
        to_string(merged[:cache_type_v] || "q8_0"),
        "--batch-size",
        to_string(merged[:batch_size] || 1024),
        "--ubatch-size",
        to_string(merged[:ubatch_size] || 1024),
        "--parallel",
        to_string(merged[:parallel] || 1),
        "--threads",
        to_string(merged[:threads] || 12),
        "--threads-batch",
        to_string(merged[:threads_batch] || 24)
      ] ++
        role_specific_args(role, merged) ++
        boolean_flag("--cont-batching", merged[:cont_batching]) ++
        boolean_flag("--cache-prompt", merged[:cache_prompt]) ++
        boolean_flag("--kv-unified", merged[:kv_unified]) ++
        boolean_flag("--jinja", merged[:jinja]) ++
        boolean_flag("--metrics", merged[:metrics]) ++
        load_mode_flag(merged[:no_mmap]) ++
        optional_flag("--flash-attn", merged[:flash_attn]) ++
        optional_flag("--slot-save-path", merged[:slot_save_path]) ++
        optional_flag("--reasoning-format", merged[:reasoning_format]) ++
        optional_flag("--temp", merged[:temp], &Float.to_string/1) ++
        optional_flag("--top-p", merged[:top_p], &Float.to_string/1) ++
        optional_flag("--top-k", merged[:top_k]) ++
        optional_flag("--keep", merged[:keep]) ++
        optional_flag("--n-predict", merged[:n_predict]) ++
        optional_flag("--prio", merged[:prio]) ++
        optional_flag("--slot-prompt-similarity", merged[:slot_prompt_similarity]) ++
        optional_flag("--spec-type", merged[:spec_type]) ++
        optional_flag("--spec-ngram-mod-n-min", merged[:spec_ngram_mod_n_min]) ++
        optional_flag("--spec-ngram-mod-n-max", merged[:spec_ngram_mod_n_max]) ++
        optional_flag("--spec-ngram-mod-n-match", merged[:spec_ngram_mod_n_match]) ++
        optional_flag("--embedding", merged[:embedding]) ++
        optional_flag("--pooling", merged[:pooling]) ++
        optional_flag("--embd-normalize", merged[:embd_normalize]) ++
        optional_flag("--device", merged[:device]) ++
        boolean_flag("--no-kv-offload", merged[:no_kv_offload]) ++
        boolean_flag("--no-op-offload", merged[:no_op_offload]) ++
        boolean_flag("--no-host", merged[:no_host]) ++
        boolean_flag("--no-mmproj-offload", merged[:no_mmproj_offload]) ++
        optional_flag("--fit", merged[:fit]) ++
        (config[:extra_args] || [])
  end

  defp role_specific_args(:chat, _merged), do: []

  # `--embedding` is handled by `optional_flag/3` below for both roles,
  # so this clause is intentionally empty.
  defp role_specific_args(:embedding, _merged), do: []

  # If `n_gpu_layers` is `:auto`, resolve from the hardware plan.
  defp maybe_apply_device(merged, %{device: :cpu}), do: Map.put(merged, :n_gpu_layers, 0)
  defp maybe_apply_device(merged, %{device: :gpu}), do: Map.put(merged, :n_gpu_layers, 99)
  defp maybe_apply_device(merged, _), do: merged

  defp boolean_flag(flag, true), do: [flag]
  defp boolean_flag(_flag, _), do: []

  # nil/false cases first — they must match before the general one.
  # Note: `true` is intentionally NOT mapped to `[flag, "true"]` because
  # most llama-server args are pure flags (no value). The caller passes
  # `true` to mean "enable this flag"; the result is just `[flag]`.
  defp optional_flag(_flag, nil, _formatter), do: []
  defp optional_flag(_flag, false, _formatter), do: []
  defp optional_flag(flag, true, _formatter), do: [flag]

  defp optional_flag(flag, value, formatter) when not is_boolean(value) and value != false,
    do: [flag, formatter.(value)]

  # 2-arity version (formatter defaults to to_string/1).
  defp optional_flag(_flag, nil), do: []
  defp optional_flag(_flag, false), do: []
  defp optional_flag(flag, true), do: [flag]

  defp optional_flag(flag, value) when not is_boolean(value) and value != false,
    do: [flag, to_string(value)]

  defp optional_flag(_flag, _), do: []

  # Maps `no_mmap: true` → `--load-mode none` (replaces deprecated `--no-mmap`).
  defp load_mode_flag(true), do: ["--load-mode", "none"]
  defp load_mode_flag(_), do: []

  @doc """
  Spawns a `llama-server` subprocess and waits for it to become
  ready. Returns `{:ok, :started}` (GPU) or `{:ok, :started_cpu}`
  depending on the device resolved during `build_args/2`. Returns
  `:already_running` if the server was already reachable before
  the attempt.

  ## Options

    * `:force` — kill the existing server and re-spawn.
    * `:health_check` — override the health probe (defaults to
      `GET /health`). Receives the port.
    * `:wait_timeout` — max ms to wait for readiness (default 30 s).
  """
  @spec start(role(), config(), keyword()) ::
          :already_running
          | {:ok, :started}
          | {:ok, :started_cpu}
          | {:error, term()}
  def start(role, config, opts \\ []) do
    Application.ensure_all_started(:arrea)

    port = config[:port]
    health = Keyword.get(opts, :health_check, &default_health/1)
    force = Keyword.get(opts, :force, false)
    id = Keyword.get(opts, :id, :"#{role}_server")
    server_id = Keyword.get(opts, :server_id, :"delfos_#{role}_server")

    if force, do: Arrea.LongRunning.stop(server_id)

    if running?(port) do
      :already_running
    else
      do_start(role, config, id, server_id, health, opts)
    end
  end

  defp do_start(role, config, id, server_id, health, opts) do
    case find_binary(opts) do
      {:ok, binary} ->
        # The slot-save-path directory must exist before llama-server starts,
        # otherwise it exits with code 1 ("not a directory").
        config |> Map.get(:slot_save_path) |> ensure_dir!()

        args = build_args(role, config)
        wait_timeout = Keyword.get(opts, :wait_timeout, 30_000)

        case Arrea.LongRunning.start_link(
               id: server_id,
               binary: binary,
               args: args,
               health: health,
               stop_grace: 5_000,
               name: id
             ) do
          {:ok, _pid} ->
            case wait_until_ready(config[:port], wait_timeout) do
              :ok ->
                device = device_of(config)
                if device == :cpu, do: {:ok, :started_cpu}, else: {:ok, :started}

              {:error, _} = err ->
                err
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Stops the server registered under the given `server_id`. Idempotent.
  """
  @spec stop(keyword()) :: :ok
  def stop(opts \\ []) do
    server_id = Keyword.get(opts, :server_id, :llama_server_default)
    Arrea.LongRunning.stop(server_id)
    :ok
  end

  @doc """
  Probes the `/health` endpoint of a running `llama-server`.

  ## Examples

      iex> Botica.Batteries.LlamaServer.running?(9999)
      true
  """
  @spec running?(pos_integer()) :: boolean()
  def running?(port) when is_integer(port) do
    case Apero.Http.get("http://127.0.0.1:#{port}/health", [], receive_timeout: 1_000) do
      {:ok, %{status: status}} when status in 200..299 -> true
      _ -> false
    end
  rescue
    _ -> false
  catch
    :exit, _ -> false
  end

  defp default_health(port) do
    fn ->
      case running?(port) do
        true -> :ok
        false -> {:error, :not_ready}
      end
    end
  end

  defp wait_until_ready(port, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout

    # Poll the server with a 200 ms cadence until it's ready, or fall
    # through to the timeout branch if `deadline` elapses.
    poll(port, deadline)
  end

  defp poll(port, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      {:error, :timeout_waiting_for_server}
    else
      Process.sleep(200)
      if running?(port), do: :ok, else: poll(port, deadline)
    end
  end

  defp device_of(config) do
    case config[:hardware_plan] do
      %{device: device} -> device
      _ -> :gpu
    end
  end

  @doc """
  Builds a ready-to-use `Botica.Check` definition for `:chat` or
  `:embedding` so the role can show up in `Botica.Doctor.run/1`
  output. Pass the same `config` you would pass to `start/3`.

  ## Examples

      Botica.Doctor.run(%{
        app_name: "delfos",
        checks: [
          Botica.Batteries.LlamaServer.check(:chat, %{port: 9999, ...}),
          Botica.Batteries.LlamaServer.check(:embedding, %{port: 9998, ...})
        ]
      })
  """
  @spec check(role(), config()) :: Botica.Check.Behaviour.spec()
  def check(role, config) do
    %{
      id: String.to_atom("llama_server_#{role}"),
      name: "llama-server (#{role})",
      description: "Chat completion / embedding server (port #{config[:port]})",
      priority: 1,
      tags: [:llm, :local],
      check: fn -> check_server(config[:port], role) end,
      fix_command: "Run `delfos config llm` to install/configure"
    }
  end

  defp check_server(port, role) do
    if running?(port) do
      {:ok, "#{role} server responsive on port #{port}"}
    else
      {:error, "#{role} server not responding on port #{port}"}
    end
  end

  # Creates the directory for `slot_save_path` if it doesn't exist.
  # llama-server requires this directory to already exist; missing it
  # causes exit code 1 with "not a directory".
  defp ensure_dir!(nil), do: :ok

  defp ensure_dir!(path) when is_binary(path) do
    File.mkdir_p!(path)
  rescue
    e ->
      Logger.warning(
        "[LlamaServer] could not create slot_save_path #{path}: #{Exception.message(e)}"
      )
  end
end
