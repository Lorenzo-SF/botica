defmodule Botica.FacadeTest do
  @moduledoc """
  Tests for the `Botica` facade module (delegates).
  """

  use ExUnit.Case, async: true

  alias Botica.Flags.Store

  defp config do
    %{
      app_name: "facade_test_app",
      checks: [
        %{
          id: :ok_check,
          name: "OK check",
          description: "always passes",
          priority: 1,
          tags: [:test],
          timeout: 1_000,
          check: fn -> {:ok, "fine"} end,
          fix: nil,
          fix_command: nil
        }
      ]
    }
  end

  setup do
    Store.table() |> :ets.delete_all_objects()
    :ok
  end

  test "run/1 delegates to Doctor" do
    assert {:ok, results} = Botica.run(config())
    assert [%{id: :ok_check, status: :ok}] = results
  end

  test "run/2 passes options through" do
    assert {:ok, _} = Botica.run(config(), timeout: 2_000, parallel: true)
  end

  test "health_check/1 returns a status map" do
    assert %{status: :ok, summary: %{error: 0, passed?: true}} = Botica.health_check(config())
  end

  test "validate/1 returns :ok for a valid config" do
    assert :ok = Botica.validate(config())
  end

  test "batteries/0 lists predefined checks" do
    batteries = Botica.batteries()
    assert is_list(batteries)
    assert Enum.all?(batteries, &(&1.id in [:postgresql, :redis, :memory, :disk]))
  end

  test "flags delegates work through the facade" do
    :ok = Botica.define(:facade_flag, default: true)
    assert Botica.enabled?(:facade_flag)
    assert {:ok, %{name: :facade_flag}} = Botica.get(:facade_flag)
    assert Botica.count() >= 1
    assert is_list(Botica.all())

    :ok = Botica.set(:facade_flag, enabled: false)
    refute Botica.enabled?(:facade_flag)

    :ok = Botica.enable(:facade_flag)
    assert Botica.enabled?(:facade_flag)

    :ok = Botica.disable(:facade_flag)
    refute Botica.enabled?(:facade_flag)

    :ok = Botica.delete(:facade_flag)
    assert :error = Botica.get(:facade_flag)
  end

  test "enabled?/2 with rollout entity works through the facade" do
    :ok = Botica.define(:facade_rollout, default: false, rollout: 0)
    :ok = Botica.enable(:facade_rollout)
    refute Botica.enabled?(:facade_rollout, for: "someone")
    refute Botica.enabled?(:facade_rollout, %{"user" => "someone"})
  end
end
