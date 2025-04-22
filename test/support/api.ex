defmodule AshNeo4j.Test.Domain do
  @moduledoc false
  use Ash.Domain

  resources do
    resource(AshNeo4j.Test.Post)
    resource(AshNeo4j.Test.Comment)
  end
end
