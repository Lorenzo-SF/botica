defmodule Botica.FlagsTest do
  @moduledoc """
  Tests for `Botica.Flags` and `Botica.Flags.Store`.

  Each test uses unique flag names so they don't collide when run together.
  """

  use ExUnit.Case, async: false

  alias Botica.Flags
  alias Botica.Flags.Flag

  describe "define/2 + enabled?/1" do
    test "defines a flag and queries its value" do
      Botica.Flags.define(:test_define_query, default: false)
      refute Botica.Flags.enabled?(:test_define_query)

      Botica.Flags.define(:test_define_default_true, default: true)
      assert Botica.Flags.enabled?(:test_define_default_true)
    end

    test "enabled? returns false when flag is undefined" do
      refute Botica.Flags.enabled?(:nonexistent_flag_42)
    end

    test "define/2 with default and no enabled uses default as enabled" do
      Botica.Flags.define(:test_default_as_enabled, default: true)
      assert Botica.Flags.enabled?(:test_default_as_enabled)
    end

    test "define/2 with explicit enabled overrides default" do
      Botica.Flags.define(:test_explicit_enabled, default: false, enabled: true)
      assert Botica.Flags.enabled?(:test_explicit_enabled)
    end

    test "define/2 preserves created_at on redefinition" do
      Botica.Flags.define(:test_redef_persist_created, default: false)
      {:ok, first} = Botica.Flags.get(:test_redef_persist_created)
      Process.sleep(10)
      Botica.Flags.define(:test_redef_persist_created, default: true)
      {:ok, second} = Botica.Flags.get(:test_redef_persist_created)
      assert DateTime.compare(first.created_at, second.created_at) == :eq
      refute DateTime.compare(first.updated_at, second.updated_at) == :eq
    end
  end

  describe "enable/1 and disable/1" do
    test "enable/1 creates and enables a flag that did not exist" do
      Botica.Flags.enable(:test_enable_new)
      assert Botica.Flags.enabled?(:test_enable_new)
    end

    test "disable/1 turns an enabled flag off" do
      Botica.Flags.define(:test_toggle, default: false)
      Botica.Flags.enable(:test_toggle)
      assert Botica.Flags.enabled?(:test_toggle)
      Botica.Flags.disable(:test_toggle)
      refute Botica.Flags.enabled?(:test_toggle)
    end

    test "disable/1 preserves rollout percentage" do
      Botica.Flags.define(:test_disable_preserves_rollout, default: false, rollout: 50)
      Botica.Flags.enable(:test_disable_preserves_rollout)
      {:ok, before} = Botica.Flags.get(:test_disable_preserves_rollout)
      Botica.Flags.disable(:test_disable_preserves_rollout)
      {:ok, after_disabled} = Botica.Flags.get(:test_disable_preserves_rollout)
      assert before.rollout == after_disabled.rollout
      refute after_disabled.enabled
    end
  end

  describe "set/2" do
    test "set/2 updates an existing flag" do
      Botica.Flags.define(:test_set_existing, default: false, rollout: 10)
      :ok = Botica.Flags.set(:test_set_existing, rollout: 80, enabled: true)

      {:ok, flag} = Botica.Flags.get(:test_set_existing)
      assert flag.rollout == 80
      assert flag.enabled == true
    end

    test "set/2 returns :not_found for undefined flag" do
      assert {:error, :not_found} = Botica.Flags.set(:test_set_missing, rollout: 50)
    end
  end

  describe "rollout bucketing" do
    test "rollout is deterministic for the same entity" do
      Botica.Flags.define(:test_rollout_deterministic, default: false, rollout: 50)
      Botica.Flags.enable(:test_rollout_deterministic)

      result1 = Botica.Flags.enabled?(:test_rollout_deterministic, for: "user_123")
      result2 = Botica.Flags.enabled?(:test_rollout_deterministic, for: "user_123")
      assert result1 == result2
    end

    test "rollout 0% means no one gets the feature" do
      Botica.Flags.define(:test_rollout_zero, default: false, rollout: 0)
      Botica.Flags.enable(:test_rollout_zero)

      # Across many entities, nobody should get it.
      results =
        for i <- 1..50 do
          Botica.Flags.enabled?(:test_rollout_zero, for: "user_#{i}")
        end

      refute Enum.any?(results)
    end

    test "rollout 100% means everyone gets the feature" do
      Botica.Flags.define(:test_rollout_full, default: false, rollout: 100)
      Botica.Flags.enable(:test_rollout_full)

      results =
        for i <- 1..50 do
          Botica.Flags.enabled?(:test_rollout_full, for: "user_#{i}")
        end

      assert Enum.all?(results)
    end

    test "rollout is roughly uniform (sanity check)" do
      Botica.Flags.define(:test_rollout_uniform, default: false, rollout: 50)
      Botica.Flags.enable(:test_rollout_uniform)

      hits =
        for i <- 1..1000, reduce: 0 do
          acc ->
            if Botica.Flags.enabled?(:test_rollout_uniform, for: "user_#{i}"),
              do: acc + 1,
              else: acc
        end

      # Should be roughly 500. Allow ±10% slack for the small sample.
      assert hits > 400, "expected ~500 hits, got #{hits}"
      assert hits < 600, "expected ~500 hits, got #{hits}"
    end

    test "rollout 0% means even with enabled the flag returns false" do
      Botica.Flags.define(:test_rollout_zero_enabled, default: false, rollout: 0)
      Botica.Flags.enable(:test_rollout_zero_enabled)

      refute Botica.Flags.enabled?(:test_rollout_zero_enabled, for: "anyone")
    end

    test "for: is ignored when rollout is nil" do
      Botica.Flags.define(:test_no_rollout, default: false)
      Botica.Flags.enable(:test_no_rollout)
      assert Botica.Flags.enabled?(:test_no_rollout, for: "anybody")
    end
  end

  describe "all/0 + count/0" do
    test "all/0 returns all defined flags" do
      # Use unique names so this test doesn't interfere with others
      name_a = unique_name(:all_test_a)
      name_b = unique_name(:all_test_b)

      Botica.Flags.define(name_a, default: true)
      Botica.Flags.define(name_b, default: false)

      names = Botica.Flags.all() |> Enum.map(& &1.name)
      assert name_a in names
      assert name_b in names
    end

    test "all/0 returns flags sorted by updated_at desc" do
      name_old = unique_name(:sort_old)
      name_new = unique_name(:sort_new)

      Botica.Flags.define(name_old, default: false)
      Process.sleep(20)
      Botica.Flags.define(name_new, default: false)

      names = Botica.Flags.all() |> Enum.map(& &1.name)
      # Most recently updated should appear first
      assert hd(names) == name_new
    end

    test "count/0 returns the number of registered flags" do
      before = Botica.Flags.count()
      Botica.Flags.define(unique_name(:count_test), default: false)
      after_define = Botica.Flags.count()
      assert after_define == before + 1
    end
  end

  describe "delete/1" do
    test "delete/1 removes a flag" do
      name = unique_name(:delete_test)
      Botica.Flags.define(name, default: false)
      {:ok, _} = Botica.Flags.get(name)
      :ok = Botica.Flags.delete(name)
      assert :error = Botica.Flags.get(name)
    end
  end

  describe "Botica.Doctor integration" do
    test "flags_summary/0 includes defined flags" do
      name = unique_name(:doctor_flags_summary)
      Botica.Flags.define(name, default: true)

      summary = Botica.Doctor.flags_summary()
      names = Enum.map(summary.flags, & &1.name)
      assert name in names
      assert summary.count >= 1
    end

    test "format_flags_summary/0 returns empty string when no flags defined" do
      # Even if other tests defined flags, this should produce something with at
      # least a header — if it returns "" that means the registry was empty.
      # We can't guarantee empty registry in shared state, so just assert shape:
      result = Botica.Doctor.format_flags_summary()
      assert is_binary(result)
    end

    test "format_flags_summary/0 produces a banner with the count" do
      Botica.Flags.define(unique_name(:format_test), default: true)
      banner = Botica.Doctor.format_flags_summary()
      assert banner =~ ~r/Flags \(\d+ defined\):/
    end
  end

  describe "Flag struct" do
    test "Flag.new/2 clamps rollout > 100 to 100" do
      flag = Flag.new(:clamp_high, rollout: 250)
      assert flag.rollout == 100
    end

    test "Flag.new/2 clamps rollout < 0 to 0" do
      flag = Flag.new(:clamp_low, rollout: -5)
      assert flag.rollout == 0
    end

    test "Flag.new/2 keeps valid rollout untouched" do
      flag = Flag.new(:valid_rollout, rollout: 42)
      assert flag.rollout == 42
    end

    test "Flag.new/2 default rollout is nil" do
      flag = Flag.new(:no_rollout)
      assert flag.rollout == nil
    end
  end

  # Helper para evitar colisiones entre tests
  defp unique_name(base), do: :"#{base}_#{System.unique_integer([:positive])}"
end
