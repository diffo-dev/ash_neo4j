# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.BoltxHelper do
  @moduledoc """
  AshNeo4j BoltxHelper
  """

  @dialyzer {:nowarn_function, start: 1}
  @doc """
  Starts Boltx, returns :ok or {:error, error}
  """
  def start() do
    start(Application.get_env(:boltx, Bolt))
  end

  @doc """
  Starts Boltx with config, returns :ok or {:error, error}
  """
  def start(config) do
    case Boltx.start_link(config) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Checks Boltx connectivity
  """
  def is_connected() do
    try do
      Boltx.query!(Bolt, "return 1 as n") |> Boltx.Response.first() == %{"n" => 1}
    catch
      :exit, _ -> false
    end
  end
end
