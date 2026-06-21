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

  @doc """
  Starts the BoltApoc pool (Neo4j 5.x Community + APOC, #386). Returns :ok,
  {:error, error}, or {:error, :not_configured} when no BoltApoc config is present.
  """
  def start_bolt_apoc() do
    case Application.get_env(:bolty, BoltApoc) do
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
  Neo4j server that supports the `CYPHER 25` language selector (date-versioned
  Neo4j ≥ 2025.06).

  Read from the negotiated `policy().cypher_25` flag (bolty ≥ 0.2.0); `false`
  when the pool is not started.
  """
  def cypher25?(), do: cypher25?(current_pool())

  @doc "Cypher 25 support for an explicit `pool`."
  def cypher25?(pool) do
    case policy(pool) do
      %{cypher_25: cypher_25} -> cypher_25
      nil -> false
    end
  end

  @doc """
  Returns `true` when the current pool (see `current_pool/0`) is connected to a
  Neo4j server that supports dynamic labels/types (`MATCH (n:$(expr))`,
  `-[r:$(expr)]->`), which landed in Neo4j 5.26.

  This is the **server-feature axis**, distinct from `cypher25?/0`: dynamic
  labels run under plain `CYPHER 5` and need no `CYPHER 25` selector, so a
  5.26 server reports `dynamic_labels: true` but `cypher_25: false`. Read from
  the negotiated `policy().dynamic_labels` flag (bolty ≥ 0.2.0); `false` when the
  pool is not started.
  """
  def dynamic_labels?(), do: dynamic_labels?(current_pool())

  @doc "Dynamic label/type support for an explicit `pool`."
  def dynamic_labels?(pool) do
    case policy(pool) do
      %{dynamic_labels: dynamic_labels} -> dynamic_labels
      nil -> false
    end
  end

  @doc """
  Returns `true` when the current pool (see `current_pool/0`) is connected to a
  Neo4j server with **APOC** installed (#386) — useful as a deploy/start-up
  healthcheck before relying on an `apoc.*` `fragment(...)`.

  Unlike `cypher25?/0` / `dynamic_labels?/0` (negotiated server features), APOC is
  a plugin, so this introspects the server with `SHOW PROCEDURES`. Cached in
  `:persistent_term` per pool after the first call. `false` when the pool is not
  started. Installing APOC is the operator's job — this only reports it.
  """
  def apoc_available?(), do: apoc_available?(current_pool())

  @doc "APOC availability for an explicit `pool`."
  def apoc_available?(pool) do
    case :persistent_term.get({__MODULE__, :apoc, pool}, :not_cached) do
      :not_cached ->
        available = query_apoc_available?(pool)
        :persistent_term.put({__MODULE__, :apoc, pool}, available)
        available

      cached ->
        cached
    end
  end

  defp query_apoc_available?(pool) do
    case Bolty.query(pool, "SHOW PROCEDURES YIELD name WHERE name STARTS WITH 'apoc' RETURN count(name) > 0 AS available") do
      {:ok, %Bolty.Response{results: [%{"available" => available} | _]}} -> available == true
      _ -> false
    end
  rescue
    _ -> false
  end
end
