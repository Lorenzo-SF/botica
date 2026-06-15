defmodule Botica.Types do
  @moduledoc """
  Shared types and data structures for Botica.
  """

  @type status :: :ok | :warning | :error
  @type check_id :: atom()
  @type check_result :: {:ok, String.t()} | {:warning, String.t()} | {:error, String.t()}
  @type fix_result :: {:ok, String.t()} | {:error, String.t()} | :skipped

  @type result :: %{
          id: check_id,
          name: String.t(),
          status: status,
          message: String.t(),
          fix_command: String.t() | nil
        }

  @type summary :: %{
          ok: non_neg_integer(),
          warning: non_neg_integer(),
          error: non_neg_integer(),
          total: non_neg_integer(),
          passed?: boolean()
        }

  @type fix_report :: %{
          applied: [check_id],
          failed: [{check_id, String.t()}],
          skipped: [check_id]
        }

  @type config :: %{
          app_name: String.t(),
          checks: [check_def]
        }

  @type check_def :: %{
          id: check_id,
          name: String.t(),
          description: String.t(),
          priority: non_neg_integer(),
          tags: [atom()] | [],
          timeout: non_neg_integer() | nil,
          check: (-> check_result),
          fix: (-> fix_result) | nil,
          fix_command: String.t() | nil
        }

  @type executor_option ::
          {:timeout, non_neg_integer()}
          | :stop_on_first_error
          | :continue_on_error

  @type executor_options :: [executor_option()]
end
