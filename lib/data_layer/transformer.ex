defmodule AshNeo4j.DataLayer.Transformer do
  @moduledoc false
  use Spark.Dsl.Transformer

  def transform(dsl) do
    {:ok, dsl}
  end
end
