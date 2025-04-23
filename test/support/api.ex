defmodule AshNeo4j.Test.Domain do
  @moduledoc false
  use Ash.Domain

  resources do
    resource(AshNeo4j.Test.Resource.Post)
    resource(AshNeo4j.Test.Resource.Comment)
  end
end
