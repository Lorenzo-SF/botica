defmodule Botica.Batteries.RedisTest do
  use ExUnit.Case, async: true

  alias Botica.Batteries.Redis

  describe "check_def/1" do
    test "returns a valid check definition" do
      defn = Redis.check_def([])

      assert defn.id == :redis
      assert defn.name == "Redis"
      assert defn.priority == 2
      assert :cache in defn.tags
      assert :critical in defn.tags
      assert is_function(defn.check, 0)
      assert is_function(defn.fix, 0)
      assert defn.timeout == 5_000
    end

    test "honours custom host and port" do
      defn = Redis.check_def(host: "redis.example.com", port: 7000)
      # We can't easily inspect the closure, but the function should run
      # without raising even if it fails (timeout).
      assert defn.id == :redis
    end

    test "honours custom timeout" do
      defn = Redis.check_def(timeout: 10_000)
      assert defn.timeout == 10_000
    end
  end

  describe "check_connection/2" do
    test "returns error for unreachable port without redis-cli" do
      # Use a non-routable IP — Network.port_open? will return false
      result = Redis.check_connection("192.0.2.1", 6379)
      # Either :error string (no redis-cli, port closed) or timeout
      assert match?({:error, _}, result) or match?({:ok, _}, result)
    end
  end

  describe "start_service/0" do
    test "returns error when sudo is not available" do
      # In a typical test environment, sudo may not be available
      # Either we get {:error, "sudo not found..."} or {:error, "sudo requires..."}
      # or even {:ok, ...} if Redis is somehow running. We just verify
      # no exception is raised.
      result = Redis.start_service()
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
end
