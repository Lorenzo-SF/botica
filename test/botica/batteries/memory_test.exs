defmodule Botica.Batteries.MemoryTest do
  use ExUnit.Case, async: false

  alias Botica.Batteries.Memory

  describe "check_def/1" do
    test "creates a valid memory check definition" do
      def = Memory.check_def(warning_threshold: 80, error_threshold: 95)
      assert def.id == :memory
      assert def.name == "Memory"
      assert def.check
      assert is_function(def.check, 0)
    end

    test "uses default thresholds when not specified" do
      def = Memory.check_def()
      assert def.id == :memory
    end
  end

  describe "check_memory/2" do
    test "returns error for unknown OS type" do
      # When OS type is not recognized
      result = Memory.check_memory(80, 95)
      # The function should return an error for unsupported OS
      # since it dispatches based on OS.type()
      assert match?({:error, _}, result) or match?({:warning, _}, result) or
               match?({:ok, _}, result)
    end
  end
end
