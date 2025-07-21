defmodule AshNeo4j.Test.Resource.Author do
  @moduledoc false
  use Ash.Resource,
    domain: AshNeo4j.Test.Domain,
    data_layer: AshNeo4j.DataLayer

  neo4j do
    label :Author
    relate [{:posts, :WROTE, :outgoing}]
    translate id: :uuid
    skip [:post_id]
  end

  actions do
    default_accept :*
    defaults [:create, :destroy]

    read :read do
      primary? true
    end

    update :update do
      primary? true
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :post_id, :uuid
  end

  relationships do
    has_many :posts, AshNeo4j.Test.Resource.Post, public?: true
  end
end
