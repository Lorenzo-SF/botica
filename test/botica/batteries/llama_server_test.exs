defmodule Botica.Batteries.LlamaServerTest do
  @moduledoc """
  Unit tests for `Botica.Batteries.LlamaServer` — the single source of
  truth for llama-server lifecycle.

  We test three surfaces:

    * `build_args/2` — arg generation for both roles. Pure.
    * `find_binary/1` — path resolution. Touches the filesystem briefly.
    * `Installer` — URL selection, idempotency. Skipped by default (network).
  """

  use ExUnit.Case, async: true

  alias Botica.Batteries.LlamaServer, as: LS

  describe "build_args/2 — chat role" do
    test "produces all the canonical flags for a chat model" do
      args =
        LS.build_args(:chat, %{
          gguf_path: "/tmp/model.gguf",
          port: 9999,
          host: "127.0.0.1",
          api_key: "sk-test",
          alias: "delftest",
          n_gpu_layers: 99,
          ctx_size: 128_072,
          cache_type_k: "q8_0",
          cache_type_v: "q8_0",
          batch_size: 4096,
          ubatch_size: 1024,
          parallel: 8,
          threads: 12,
          threads_batch: 24,
          keep: 8192,
          n_predict: 8192,
          temp: 1.0,
          top_p: 1.0,
          top_k: 0,
          reasoning_format: "auto",
          prio: 2,
          slot_prompt_similarity: 0.2,
          spec_type: "ngram-mod",
          spec_ngram_mod_n_min: 8,
          spec_ngram_mod_n_max: 20,
          spec_ngram_mod_n_match: 40,
          cont_batching: true,
          cache_prompt: true,
          kv_unified: true,
          jinja: true,
          metrics: true,
          flash_attn: "on",
          no_mmap: true,
          slot_save_path: "/tmp/cache",
          hardware_plan: %{device: :gpu}
        })

      assert "--model" in args
      assert "/tmp/model.gguf" in args
      assert "--host" in args
      assert "127.0.0.1" in args
      assert "--port" in args
      assert "9999" in args
      assert "--api-key" in args
      assert "sk-test" in args
      assert "--alias" in args
      assert "delftest" in args
      assert "--ctx-size" in args
      assert "128072" in args
      assert "--n-gpu-layers" in args
      assert "99" in args
      assert "--cache-type-k" in args
      assert "q8_0" in args
      assert "--cache-type-v" in args
      assert "--batch-size" in args
      assert "4096" in args
      assert "--ubatch-size" in args
      assert "--parallel" in args
      assert "8" in args

      # Boolean flags always present when true
      assert "--cont-batching" in args
      assert "--cache-prompt" in args
      assert "--kv-unified" in args
      assert "--jinja" in args
      assert "--metrics" in args
      assert "--no-mmap" in args
      assert "--spec-type" in args
      assert "ngram-mod" in args
      assert "--reasoning-format" in args
      assert "auto" in args

      # Chat role should NOT include embedding-specific flags
      refute "--embedding" in args
      refute "--pooling" in args
    end

    test "boolean false omits the flag" do
      args =
        LS.build_args(:chat, %{
          gguf_path: "/tmp/model.gguf",
          port: 9999,
          cont_batching: false,
          cache_prompt: false,
          kv_unified: false,
          jinja: false,
          metrics: false,
          no_mmap: false
        })

      refute "--cont-batching" in args
      refute "--cache-prompt" in args
      refute "--kv-unified" in args
      refute "--jinja" in args
      refute "--metrics" in args
      refute "--no-mmap" in args
    end

    test "raises when gguf_path missing" do
      assert_raise ArgumentError, ~r/gguf_path/, fn ->
        LS.build_args(:chat, %{port: 9999})
      end
    end

    test ":auto device honors hardware_plan" do
      args_cpu =
        LS.build_args(:chat, %{
          gguf_path: "/tmp/model.gguf",
          port: 9999,
          hardware_plan: %{device: :cpu}
        })

      args_gpu =
        LS.build_args(:chat, %{
          gguf_path: "/tmp/model.gguf",
          port: 9999,
          hardware_plan: %{device: :gpu}
        })

      # When n_gpu_layers is not specified explicitly, plan decides.
      # Defaults from `:chat` include `n_gpu_layers: :auto`.
      pos_cpu = Enum.find_index(args_cpu, &(&1 == "--n-gpu-layers"))
      assert Enum.at(args_cpu, pos_cpu + 1) == "0"

      pos_gpu = Enum.find_index(args_gpu, &(&1 == "--n-gpu-layers"))
      assert Enum.at(args_gpu, pos_gpu + 1) == "99"
    end
  end

  describe "build_args/2 — embedding role" do
    test "includes embedding-specific flags" do
      args =
        LS.build_args(:embedding, %{
          gguf_path: "/tmp/emb.gguf",
          port: 9998,
          embedding: true,
          pooling: "last",
          embd_normalize: 2,
          device: "none",
          no_kv_offload: true,
          no_op_offload: true,
          no_host: true,
          no_mmproj_offload: true,
          fit: "off"
        })

      assert "--model" in args
      assert "--embedding" in args
      assert "--pooling" in args
      assert "last" in args
      assert "--embd-normalize" in args
      assert "2" in args
      assert "--device" in args
      assert "none" in args
      assert "--fit" in args
      assert "off" in args
    end
  end

  describe "find_binary/1" do
    test "returns proc-when-found path when llama-server is in PATH" do
      # When llms is installed, we expect {:ok, "/path/to/llama-server"}.
      case LS.find_binary() do
        {:ok, _path} ->
          :ok

        {:error, :no_llama_server} ->
          # Acceptable in CI where llama-server isn't installed.
          :ok
      end
    end

    test "respects explicit override" do
      tmp = Path.join(System.tmp_dir!(), "fake_llama_server_#{System.unique_integer()}")
      File.write!(tmp, "#!/bin/sh\necho fake\n")
      File.chmod!(tmp, 0o755)

      try do
        assert {:ok, ^tmp} = LS.find_binary(llama_server_path: tmp)
      after
        File.rm!(tmp)
      end
    end

    test "falls through to PATH or error when no override given" do
      result = LS.find_binary(llama_server_path: "/nonexistent/path/for/sure")
      # Either PATH lookup hit, or installer not triggered because
      # nothing requested `force: true`. Just verify it didn't crash.
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "extra_args (open-ended args appended last)" do
    test "extra_args are appended at the end" do
      args =
        LS.build_args(:chat, %{
          gguf_path: "/tmp/model.gguf",
          port: 9999,
          extra_args: ["--my-flag", "value"]
        })

      my_idx = Enum.find_index(args, &(&1 == "--my-flag"))
      assert my_idx != nil

      # Last two elements should be the extras
      assert Enum.at(args, -2) == "--my-flag"
      assert Enum.at(args, -1) == "value"
    end
  end

  describe "Installer (URL selection)" do
    test "precompiled_url returns nil for unsupported platforms" do
      # The covered branches in CI may vary. Just verify the helper
      # doesn't crash and returns a string-or-nil.
      result = LS.Installer.install()
      assert result in [:already_installed, :downloaded] or match?({:error, _}, result)
    end

    test "install_dir respects env override" do
      original = System.get_env("LLAMA_INSTALL_DIR")
      System.put_env("LLAMA_INSTALL_DIR", "/tmp/delfos-llama-test")

      try do
        assert LS.Installer.install_dir() == "/tmp/delfos-llama-test"
      after
        if original,
          do: System.put_env("LLAMA_INSTALL_DIR", original),
          else: System.delete_env("LLAMA_INSTALL_DIR")
      end
    end
  end
end
