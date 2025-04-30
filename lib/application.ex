defmodule AshNeo4j.Application do
  use Application
  @moduledoc """
  A Neo4j datalayer for the Ash framework

  For DSL documentation, see `AshNeo4j.DataLayer`
  """

  @spec start(any(), any()) :: {:error, any()} | {:ok, pid()}
  def start(_type, _args) do
    children = [
      {Boltx, Application.get_env(:boltx, Bolt)}
    ]

    opts = [strategy: :one_for_one, name: AshNeo4j.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
