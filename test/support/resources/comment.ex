defmodule AshNeo4j.Test.Comment do
  @moduledoc false
  use Ash.Resource,
    domain: AshNeo4j.Test.Domain,
    data_layer: AshNeo4j.DataLayer

  neo4j do
    label(:Comment)
    store([:title])
    translate(id: :uuid)
  end

  actions do
    default_accept(:*)
    defaults([:read])
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string, public?: true)
  end

  relationships do
    belongs_to(:post, AshNeo4j.Test.Post, public?: true)
  end
end
