defmodule AshNeo4j.DataLayer.Info do
  @moduledoc "Introspection helpers for AshNeo4j.DataLayer"

  alias Spark.Dsl.Extension

  def label(resource) do
    Extension.get_opt(resource, [:neo4j], :label, nil, true)
  end

  def store(resource) do
    Extension.get_opt(resource, [:neo4j], :store, [], true)
  end

  def translate(resource) do
    Extension.get_opt(resource, [:neo4j], :translate, [], true)
  end
end
