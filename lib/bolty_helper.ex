# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.BoltyHelper do
  @moduledoc """
  AshNeo4j BoltyHelper
  """

  @dialyzer {:nowarn_function, start: 1}
  @doc """
  Starts Bolty, returns :ok or {:error, error}
  """
  def start() do
    start(Application.get_env(:bolty, Bolt))
  end

  @doc """
  Starts Bolty with config, returns :ok or {:error, error}
  """
  def start(config) do
    case Bolty.start_link(config) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Starts the Bolt6 pool (Neo4j 2026.05, Bolt 6.0). Returns :ok, {:error, error},
  or {:error, :not_configured} when no Bolt6 config is present.
  """
  def start_bolt6() do
    case Application.get_env(:bolty, Bolt6) do
      nil -> {:error, :not_configured}
      config -> start(config)
    end
  end

  @default_pool Bolt

  @doc """
  The Bolty pool the data layer should use for the current process.

  Defaults to the primary `Bolt` pool. Override per-process with `with_pool/2`
  (or by setting `:ash_neo4j_pool` in the process dictionary) — used to route a
  test's queries and capability checks to a different Neo4j server (e.g. the
  Bolt 6.0 / Cypher 25 pool).
  """
  def current_pool(), do: Process.get(:ash_neo4j_pool, @default_pool)

  @doc """
  Runs `fun` with the data-layer pool overridden to `pool` for the current
  process, restoring the previous value afterwards. Query execution and the
  `policy/0` / `cypher25?/0` capability checks all follow the override.
  """
  def with_pool(pool, fun) when is_function(fun, 0) do
    prev = Process.get(:ash_neo4j_pool)
    Process.put(:ash_neo4j_pool, pool)

    try do
      fun.()
    after
      if prev, do: Process.put(:ash_neo4j_pool, prev), else: Process.delete(:ash_neo4j_pool)
    end
  end

  @doc """
  Checks Bolty connectivity
  """
  def is_connected() do
    try do
      Bolty.query!(Bolt, "return 1 as n") |> Bolty.Response.first() == %{"n" => 1}
    catch
      :exit, _ -> false
    end
  end

  @doc """
  Returns the negotiated `%Bolty.Policy{}` for the current pool (see
  `current_pool/0`), or `nil` when that pool is not started. Cached per pool in
  `:persistent_term` after the first call.
  """
  def policy(), do: policy(current_pool())

  @doc "Returns the `%Bolty.Policy{}` for an explicit `pool`, or `nil` when not started."
  def policy(pool) do
    case :persistent_term.get({__MODULE__, :policy, pool}, :not_cached) do
      :not_cached ->
        try do
          %{policy: policy} = Bolty.connection_info(pool)
          :persistent_term.put({__MODULE__, :policy, pool}, policy)
          policy
        catch
          :exit, _ -> nil
        end

      policy ->
        policy
    end
  end

  @doc """
  Returns `true` when the current pool (see `current_pool/0`) is connected to a
  Neo4j server that supports Cypher 25 (date-versioned Neo4j ≥ 2025.06).

  Derived from the `server_version` string in `Bolty.connection_info/1` and
  cached per pool in `:persistent_term`. Once diffo-dev/bolty#47 lands this can
  be simplified to reading `policy().cypher25` directly.
  """
  def cypher25?(), do: cypher25?(current_pool())

  @doc "Cypher 25 support for an explicit `pool`."
  def cypher25?(pool) do
    case :persistent_term.get({__MODULE__, :cypher25, pool}, :not_cached) do
      :not_cached ->
        try do
          %{server_version: server_version} = Bolty.connection_info(pool)
          result = cypher25_from_server_version(server_version)
          :persistent_term.put({__MODULE__, :cypher25, pool}, result)
          result
        catch
          :exit, _ -> false
        end

      cached ->
        cached
    end
  end

  defp cypher25_from_server_version("Neo4j/" <> rest) do
    case Regex.run(~r/^(\d{4})\.(\d{2})\./, rest) do
      [_, year, month] ->
        String.to_integer(year) * 100 + String.to_integer(month) >= 202_506

      nil ->
        false
    end
  end

  defp cypher25_from_server_version(_), do: false
end
