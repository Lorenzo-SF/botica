defmodule Botica.Batteries.LlamaServer.Installer do
  @moduledoc """
  Downloads a precompiled `llama-server` binary into a stable install
  directory (`~/models/llama-server` by default, override with
  `LLAMA_INSTALL_DIR`) so subsequent runs don't re-download.

  Detects OS + arch and picks the matching release artifact URL.
  Linux x86_64 and macOS arm64 are supported today; other platforms
  raise `:unsupported_platform`.
  """

  require Logger
  alias Apero.Proc

  @typedoc "Subcommand outcome."
  @type result :: :already_installed | :downloaded | {:error, term()}

  @doc "Where precompiled binaries live."
  @spec install_dir() :: String.t()
  def install_dir do
    case System.get_env("LLAMA_INSTALL_DIR") do
      nil -> Path.expand("~/models/llama-server")
      dir -> Path.expand(dir)
    end
  end

  @doc "Absolute path to the binary inside `install_dir/0`."
  @spec binary_path() :: String.t()
  def binary_path do
    Path.join(install_dir(), "llama-server")
  end

  @doc "True when a precompiled binary exists at `binary_path/0`."
  @spec not_installed?() :: boolean()
  def not_installed? do
    not File.exists?(binary_path())
  end

  @doc """
  Downloads and unzips the binary for the current platform. Idempotent:
  returns `:already_installed` if `binary_path/0` exists.
  """
  @spec install(keyword()) :: result()
  def install(opts \\ []) do
    dir = install_dir()
    File.mkdir_p!(dir)

    cond do
      File.exists?(binary_path()) and not Keyword.get(opts, :force, false) ->
        :already_installed

      true ->
        url = precompiled_url()

        if is_nil(url) do
          {:error, :unsupported_platform}
        else
          do_download_and_unzip(url, dir)
        end
    end
  end

  defp precompiled_url do
    case :os.type() do
      {:unix, :linux} ->
        "https://github.com/ggerganov/llama.cpp/releases/latest/download/llama-bin-linux-x64.zip"

      {:unix, :darwin} ->
        "https://github.com/ggerganov/llama.cpp/releases/latest/download/llama-bin-macos-arm64.zip"

      _ ->
        nil
    end
  end

  defp do_download_and_unzip(url, dir) do
    zip_target = Path.join(dir, "llama-server.zip")
    Logger.info("[Botica.LlamaServer] downloading #{url} → #{zip_target}")

    with :ok <- download(url, zip_target),
         :ok <- unzip(zip_target, dir),
         :ok <- cleanup(zip_target) do
      File.chmod(binary_path(), 0o755)
      :downloaded
    else
      {:error, _} = err -> err
    end
  end

  defp download(url, target) do
    case Proc.which("curl") do
      nil ->
        {:error, :curl_missing}

      _ ->
        case System.cmd("curl", ["-fL", "-o", target, url], stderr_to_stdout: true) do
          {_, 0} -> :ok
          {output, code} -> {:error, {:download_failed, code, output}}
        end
    end
  end

  defp unzip(zip_target, dir) do
    case Proc.which("unzip") do
      nil ->
        {:error, :unzip_missing}

      _ ->
        case System.cmd("unzip", ["-o", zip_target, "-d", dir], stderr_to_stdout: true) do
          {_, 0} -> :ok
          {output, code} -> {:error, {:unzip_failed, code, output}}
        end
    end
  end

  defp cleanup(zip_target) do
    File.rm(zip_target)
    :ok
  end
end
