defmodule AshNeo4j.Test.Resource.Post do
  @moduledoc false
  use Ash.Resource,
    domain: AshNeo4j.Test.Domain,
    data_layer: AshNeo4j.DataLayer

  neo4j do
    label :Post
    relate [{:comments, :BELONGS_TO, :incoming}]
    translate id: :uuid
  end

  actions do
    default_accept :*
    defaults [:read, :create, :destroy]

    update :update do
      primary? true
      require_atomic? false
      argument :add_comments, {:array, :uuid}
      accept [:score]

      change manage_relationship(:add_comments, :comments, type: :append_and_remove)
    end

    update :unrelate do
      require_atomic? false
      argument :remove_comments, {:array, :uuid}
      accept [:score]

      change manage_relationship(:remove_comments, :comments, type: :remove)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :score, :integer, public?: true, allow_nil?: true
    attribute :public, :boolean, public?: true
    attribute :unique, :string, public?: true
  end

  identities do
    identity :unique_unique, [:unique]
  end

  relationships do
    has_many :comments, AshNeo4j.Test.Resource.Comment, destination_attribute: :post_id, public?: true
  end
end
