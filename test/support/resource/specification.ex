defmodule AshNeo4j.Test.Resource.Specification do
  @moduledoc false
  use Ash.Resource,
    domain: AshNeo4j.Test.Domain,
    data_layer: AshNeo4j.DataLayer

  neo4j do
    translate id: :uuid
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :href, :string, public?: true
    attribute :name, :string, public?: true
    attribute :type, :atom, constraints: [one_of: [:service, :resource]], public?: true
    attribute :major_version, :integer, default: 1, public?: true
    attribute :minor_version, :integer, default: 0, public?: true
  end
end
