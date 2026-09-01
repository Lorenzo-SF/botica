defmodule Botica.Flags.RolloutTest do
  @moduledoc """
  Tests for `Botica.Flags.Rollout` and the context-aware `enabled?/2`.
  """

  use ExUnit.Case, async: false

  alias Botica.Flags
  alias Botica.Flags.Flag
  alias Botica.Flags.Rollout
  alias Botica.Flags.Store

  setup do
    Store.table() |> :ets.delete_all_objects()
    :ok
  end

  describe "percentage rollout" do
    test "same user always gets the same answer (determinism)" do
      Flags.define(:rollout_pct_deterministic, default: false, rollout: %{type: :percentage, value: 50})
      Flags.enable(:rollout_pct_deterministic)

      ctx = %{"user" => "user_123"}
      assert Flags.enabled?(:rollout_pct_deterministic, ctx) == Flags.enabled?(:rollout_pct_deterministic, ctx)
    end

    test "percentage 0 gives nobody, percentage 100 gives everybody" do
      Flags.define(:rollout_pct_zero, default: false, rollout: %{type: :percentage, value: 0})
      Flags.enable(:rollout_pct_zero)

      Flags.define(:rollout_pct_full, default: false, rollout: %{type: :percentage, value: 100})
      Flags.enable(:rollout_pct_full)

      for i <- 1..50 do
        refute Flags.enabled?(:rollout_pct_zero, %{"user" => "user_#{i}"})
        assert Flags.enabled?(:rollout_pct_full, %{"user" => "user_#{i}"})
      end
    end

    test "percentage 25 enables roughly a quarter of users" do
      Flags.define(:rollout_pct_25, default: false, rollout: %{type: :percentage, value: 25})
      Flags.enable(:rollout_pct_25)

      hits =
        for i <- 1..2000, reduce: 0 do
          acc -> acc + if(Flags.enabled?(:rollout_pct_25, %{"user" => "user_#{i}"}), do: 1, else: 0)
        end

      assert hits > 400, "expected ~500 hits, got #{hits}"
      assert hits < 600, "expected ~500 hits, got #{hits}"
    end

    test "legacy integer rollout still works via enabled?/2 with :for" do
      Flags.define(:rollout_legacy_int, default: false, rollout: 0)
      Flags.enable(:rollout_legacy_int)
      refute Flags.enabled?(:rollout_legacy_int, for: "anyone")
    end
  end

  describe "user_list rollout" do
    test "users in the list get the feature, others do not" do
      Flags.define(:rollout_userlist, default: false,
        rollout: %{type: :user_list, users: ["lorenzo", "ana"]}
      )

      Flags.enable(:rollout_userlist)

      assert Flags.enabled?(:rollout_userlist, %{"user" => "lorenzo"})
      assert Flags.enabled?(:rollout_userlist, %{"user" => "ana"})
      refute Flags.enabled?(:rollout_userlist, %{"user" => "pedro"})
    end

    test "user_list works with atom :user keys too" do
      Flags.define(:rollout_userlist_atom, default: false,
        rollout: %{type: :user_list, users: ["lorenzo"]}
      )

      Flags.enable(:rollout_userlist_atom)
      assert Flags.enabled?(:rollout_userlist_atom, %{user: "lorenzo"})
    end
  end

  describe "attribute rollout" do
    test "context attribute matching values gets the feature" do
      Flags.define(:rollout_attr, default: false,
        rollout: %{type: :attribute, key: "tenant", values: ["acme", "globex"]}
      )

      Flags.enable(:rollout_attr)

      assert Flags.enabled?(:rollout_attr, %{"tenant" => "acme"})
      assert Flags.enabled?(:rollout_attr, %{"tenant" => "globex"})
      refute Flags.enabled?(:rollout_attr, %{"tenant" => "initech"})
    end

    test "attribute with no matching context key is disabled" do
      Flags.define(:rollout_attr_nokey, default: false,
        rollout: %{type: :attribute, key: "tenant", values: ["acme"]}
      )

      Flags.enable(:rollout_attr_nokey)
      refute Flags.enabled?(:rollout_attr_nokey, %{})
      refute Flags.enabled?(:rollout_attr_nokey, %{"user" => "lorenzo"})
    end
  end

  describe "binary flags" do
    test "flag without rollout ignores context" do
      Flags.define(:rollout_none, default: false)
      Flags.enable(:rollout_none)

      assert Flags.enabled?(:rollout_none, %{"user" => "whoever"})
      refute Flags.enabled?(:rollout_none_disabled, %{"user" => "whoever"})
    end

    test "disabled flag is false regardless of rollout" do
      Flags.define(:rollout_disabled, default: false, rollout: %{type: :percentage, value: 100})
      refute Flags.enabled?(:rollout_disabled, %{"user" => "x"})
    end
  end

  describe "Flag.new/2 rollout normalization" do
    test "accepts map rollouts" do
      assert %{type: :percentage, value: 25} = Flag.new(:m1, rollout: %{type: :percentage, value: 25}).rollout
      assert %{type: :user_list, users: ["a"]} = Flag.new(:m2, rollout: %{type: :user_list, users: ["a"]}).rollout

      assert %{type: :attribute, key: "k", values: ["v"]} =
               Flag.new(:m3, rollout: %{type: :attribute, key: "k", values: ["v"]}).rollout
    end

    test "clamps percentage map values" do
      assert %{type: :percentage, value: 100} = Flag.new(:m4, rollout: %{type: :percentage, value: 250}).rollout
      assert %{type: :percentage, value: 0} = Flag.new(:m5, rollout: %{type: :percentage, value: -5}).rollout
    end

    test "invalid rollout definitions are ignored" do
      assert Flag.new(:m6, rollout: %{type: :percentage}).rollout == nil
      assert Flag.new(:m7, rollout: %{type: :bogus}).rollout == nil
    end
  end

  describe "Rollout.evaluate/2 directly" do
    test "nil rollout and disabled shortcuts" do
      assert Rollout.evaluate(%Flag{name: :x, enabled: true, rollout: nil}, %{})
      refute Rollout.evaluate(%Flag{name: :x, enabled: false}, %{})
    end
  end
end
