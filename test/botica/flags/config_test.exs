defmodule Botica.Flags.ConfigTest do
  @moduledoc """
  Tests for `Botica.Flags.Config`.
  """

  use ExUnit.Case, async: true

  alias Botica.Flags.Config

  setup do
    Application.delete_env(:botica, :flags)
    on_exit(fn -> Application.delete_env(:botica, :flags) end)
    :ok
  end

  test "get/0 returns empty list without config" do
    assert Config.get() == []
  end

  test "get/0 builds flags from keyword entries" do
    Application.put_env(:botica, :flags, [
      foo: [default: true, description: "foo"],
      bar: []
    ])

    flags = Config.get()
    assert length(flags) == 2
    foo = Enum.find(flags, &(&1.name == :foo))
    assert foo.default == true
    assert foo.description == "foo"
    assert Enum.find(flags, &(&1.name == :bar))
  end

  test "get/0 accepts bare atoms" do
    Application.put_env(:botica, :flags, [:bare_flag])
    flags = Config.get()
    assert [%{name: :bare_flag, default: false}] = flags
  end

  test "get/0 raises ArgumentError on malformed entries" do
    Application.put_env(:botica, :flags, ["not-an-atom"])
    assert_raise ArgumentError, ~r/Invalid flag config/, fn -> Config.get() end
  end
end
