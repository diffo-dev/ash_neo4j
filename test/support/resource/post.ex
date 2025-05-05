defmodule AshNeo4j.Test.Resource.Post do
  @moduledoc false
  use Ash.Resource,
    domain: AshNeo4j.Test.Domain,
    data_layer: AshNeo4j.DataLayer

  neo4j do
    label(:Post)
    store([:title, :score, :public, :unique])
    translate(id: :uuid)
  end

  actions do
    default_accept(:*)
    defaults([:read, :create])
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string, public?: true)
    attribute(:score, :integer, public?: true)
    attribute(:public, :boolean, public?: true)
    attribute(:unique, :string, public?: true)
  end

  identities do
    identity(:unique_unique, [:unique])
  end

  relationships do
    has_many(:comments, AshNeo4j.Test.Resource.Comment, destination_attribute: :post_id, public?: true)
  end
end
