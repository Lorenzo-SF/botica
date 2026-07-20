defmodule Botica.Flags.StoreTest do
  use ExUnit.Case, async: false

  alias Botica.Flags.Store
  alias Botica.Flags.Flag

  setup do
    # Ensure ETS table is clean before each test
    :ets.delete_all_objects(Store.table())
    :ok
  end

  test "get/1 returns :error for unknown flag" do
    assert Store.get(:nonexistent) == :error
  end

  test "put/1 and get/1 round-trip" do
    flag = Flag.new(:test_flag, default: true, description: "test")
    assert :ok = Store.put(flag)
    assert {:ok, %Flag{name: :test_flag, default: true}} = Store.get(:test_flag)
  end

  test "delete/1 removes a flag" do
    flag = Flag.new(:ephemeral, default: false)
    Store.put(flag)
    assert {:ok, _} = Store.get(:ephemeral)
    assert :ok = Store.delete(:ephemeral)
    assert Store.get(:ephemeral) == :error
  end

  test "all/0 returns registered flags" do
    a = Flag.new(:a, default: true)
    b = Flag.new(:b, default: false)
    Store.put(a)
    Store.put(b)
    result = Store.all()
    assert length(result) >= 2
  end

  test "count/0 returns number of registered flags" do
    before = Store.count()
    flag = Flag.new(:count_test, default: true)
    Store.put(flag)
    assert Store.count() == before + 1
    Store.delete(:count_test)
    assert Store.count() == before
  end

  # Named handler to avoid anonymous functions in telemetry.attach
  defp telemetry_handler(test_pid) do
    fn event_name, measurements, _metadata, _config ->
      send(test_pid, {:telemetry, event_name, measurements})
    end
  end

  setup do
    test_pid = self()

    :telemetry.attach_many(
      :botica_flags_test,
      [[:botica, :flags, :put], [:botica, :flags, :delete]],
      telemetry_handler(test_pid),
      nil
    )

    on_exit(fn ->
      :telemetry.detach(:botica_flags_test)
    end)

    :ok
  end

  test "put/1 emits telemetry event" do
    flag = Flag.new(:telemetry_test, default: true)
    Store.put(flag)

    assert_receive {:telemetry, [:botica, :flags, :put], %{value: _}}, 200

    Store.delete(:telemetry_test)
    assert_receive {:telemetry, [:botica, :flags, :delete], %{name: :telemetry_test}}, 200
  end
end
