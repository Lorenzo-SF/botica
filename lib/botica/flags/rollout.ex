defmodule Botica.Flags.Rollout do
  @moduledoc """
  Gradual rollout evaluation for feature flags.

  A rollout definition decides whether a specific entity (user, tenant,
  session…) gets the feature. Three strategies are supported:

    * `%{type: :percentage, value: 25}` — the entity falls into the
      first 25% of a deterministic hash bucket. Same entity → same
      answer across restarts.
    * `%{type: :user_list, users: ["lorenzo"]}` — explicit allow-list.
    * `%{type: :attribute, key: "tenant", values: ["acme"]}` — the
      context attribute `key` must be one of `values`.

  Legacy integer rollouts (`rollout: 25`) are treated as a percentage.

  ## Context

  The evaluation context is a map with string keys, typically the
  request context of the caller:

      %{"user" => "user_42", "tenant" => "acme", "session" => "s-1"}

  ## Determinism

  Percentage bucketing uses `:erlang.phash2/2` with a 100-bucket range,
  keyed by `{flag_name, entity}` so the same entity always lands in the
  same bucket, independent of process restarts or VM restarts.
  """

  alias Botica.Flags.Flag

  @doc """
  Evaluates a flag against a context map.

  Returns `true` when the flag is `enabled: true` AND the rollout passes
  for the context entity, `false` otherwise. A flag without rollout is
  binary: `true` iff `enabled`.
  """
  @spec evaluate(Flag.t(), map()) :: boolean()
  def evaluate(%Flag{enabled: false}, _context), do: false
  def evaluate(%Flag{enabled: true, rollout: nil}, _context), do: true

  def evaluate(%Flag{name: name, enabled: true, rollout: rollout}, context) do
    case rollout do
      pct when is_integer(pct) ->
        bucket(name, entity_for(context)) < pct

      %{type: :percentage, value: value} ->
        bucket(name, entity_for(context)) < value

      %{type: :user_list, users: users} ->
        entity_for(context) in users

      %{type: :attribute, key: key, values: values} ->
        context_value = context[key] || context[String.to_atom(key)]
        context_value in values

      _other ->
        false
    end
  end

  # The entity used for bucketing / lists: the `"user"` context key when
  # present, otherwise any stable identifier, falling back to
  # `:anonymous` for an empty context.
  defp entity_for(context) do
    cond do
      context["user"] != nil -> context["user"]
      context[:user] != nil -> context[:user]
      context["session"] != nil -> context["session"]
      map_size(context) > 0 -> Enum.sort(Map.to_list(context)) |> :erlang.phash2()
      true -> :anonymous
    end
  end

  # Deterministic 0..99 bucket for {flag_name, entity}. Using the flag
  # name in the hash keeps different flags with the same percentage from
  # granting the exact same population (they're independent rollouts).
  defp bucket(flag_name, entity) do
    :erlang.phash2({flag_name, entity}, 100)
  end
end
