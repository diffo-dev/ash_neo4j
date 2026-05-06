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
  Checks Bolty connectivity
  """
  def is_connected() do
    try do
      Bolty.query!(Bolt, "return 1 as n") |> Bolty.Response.first() == %{"n" => 1}
    catch
      :exit, _ -> false
    end
  end
end
