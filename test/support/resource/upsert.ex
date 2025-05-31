defmodule AshNeo4j.Test.Resource.Upsert do
  @moduledoc false
  use Ash.Resource,
    domain: AshNeo4j.Test.Domain,
    data_layer: AshNeo4j.DataLayer

  actions do
    default_accept :*
    defaults [:read, :destroy]

    create :create do
      accept [:first_name, :surname, :field]
      upsert? true
      upsert_identity :full_name
    end

    update :update do
      accept [:field]
    end
  end

  attributes do
    attribute :first_name, :string, public?: true, primary_key?: true, allow_nil?: false
    attribute :surname, :string, public?: true, primary_key?: true, allow_nil?: false
    attribute :field, :string, public?: true
  end

  identities do
    identity :full_name, [:first_name, :surname]
  end
end
