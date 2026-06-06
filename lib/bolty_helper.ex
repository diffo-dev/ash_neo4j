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
  Returns the negotiated `%Bolty.Policy{}` for the primary pool, or `nil` when
  the pool is not yet started. Cached in `:persistent_term` after the first call.
  """
  def policy() do
    case :persistent_term.get({__MODULE__, :policy}, :not_cached) do
      :not_cached ->
        try do
          %{policy: policy} = Bolty.connection_info(Bolt)
          :persistent_term.put({__MODULE__, :policy}, policy)
          policy
        catch
          :exit, _ -> nil
        end

      policy ->
        policy
    end
  end

  @doc """
  Returns the `%Bolty.Policy{}` for the Bolt6 pool, or `nil` when not started.
  Cached separately from the primary pool policy.
  """
  def policy(:bolt6) do
    case :persistent_term.get({__MODULE__, :policy_bolt6}, :not_cached) do
      :not_cached ->
        try do
          %{policy: policy} = Bolty.connection_info(Bolt6)
          :persistent_term.put({__MODULE__, :policy_bolt6}, policy)
          policy
        catch
          :exit, _ -> nil
        end

      policy ->
        policy
    end
  end

  @doc """
  Returns `true` when the primary pool is connected to a Neo4j server that
  supports Cypher 25 (date-versioned Neo4j ≥ 2025.06).

  Derived from the `server_version` string in `Bolty.connection_info/1` and
  cached in `:persistent_term`. Once diffo-dev/bolty#47 lands this can be
  simplified to reading `policy().cypher25` directly.
  """
  def cypher25?() do
    case :persistent_term.get({__MODULE__, :cypher25}, :not_cached) do
      :not_cached ->
        try do
          %{server_version: server_version} = Bolty.connection_info(Bolt)
          result = cypher25_from_server_version(server_version)
          :persistent_term.put({__MODULE__, :cypher25}, result)
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
