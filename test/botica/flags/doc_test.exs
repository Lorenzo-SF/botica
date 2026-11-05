defmodule Botica.Flags.DocTest do
  use ExUnit.Case, async: false

  alias Botica.Flags
  alias Botica.Flags.{Doc, Store}

  setup do
    # Ensure priv/docs directory exists
    priv_dir = Application.app_dir(:botica, "priv")
    docs_dir = Path.join(priv_dir, "docs")
    File.mkdir_p!(docs_dir)

    # Clear all flags before each test
    :ets.delete_all_objects(Store.table())
    on_exit(fn -> :ets.delete_all_objects(Store.table()) end)
    :ok
  end

  defp doc_path do
    priv_dir = Application.app_dir(:botica, "priv")
    Path.join(priv_dir, "docs/FLAGS.md")
  end

  describe "generate/0" do
    test "generates FLAGS.md with empty table when no flags" do
      assert Doc.generate() == :ok
      assert File.exists?(doc_path())
      content = File.read!(doc_path())
      assert content =~ "# Flags"
      assert content =~ "| Name | Enabled | Default | Rollout | Description |"
    end

    test "includes flag name and status in generated table" do
      Flags.define(:test_doc_flag, default: true, description: "A test flag")
      assert Doc.generate() == :ok
      content = File.read!(doc_path())
      assert content =~ ":test_doc_flag"
      assert content =~ "true"
      assert content =~ "A test flag"
    end
  end
end
