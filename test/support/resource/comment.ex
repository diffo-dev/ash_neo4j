defmodule AshNeo4j.Test.Resource.Comment do
  @moduledoc false
  use Ash.Resource,
    domain: AshNeo4j.Test.Domain,
    data_layer: AshNeo4j.DataLayer

  neo4j do
    label :Comment
    store [:title]
    translate id: :uuid
    relate [{:post, :BELONGS_TO, :outgoing}]
  end

  actions do
    default_accept :*
    defaults [:create]

    read :read do
      primary? true
    end

    update :update do
      primary? true
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
  end

  relationships do
    belongs_to :post, AshNeo4j.Test.Resource.Post, public?: true
  end
end
