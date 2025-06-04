defmodule AshNeo4j.Test.Resource.Service do
  @moduledoc false
  use Ash.Resource,
    domain: AshNeo4j.Test.Domain,
    data_layer: AshNeo4j.DataLayer

  neo4j do
    label :InternalService
    relate [
      {:specification, :SPECIFIES, :incoming},
      {:services, :MANAGES, :outgoing},
      {:resources, :USES, :outgoing}
    ]
    skip [:service_id, :parent_service_id]
    translate id: :uuid
  end

  actions do
    defaults [:destroy]

    read :read do
      primary? true
    end

    create :create do
      primary? true
      accept [:specification_id, :name]
    end

    update :update do
      primary? true
      require_atomic? false
      argument :manage_services, {:array, :uuid}
      argument :use_resources, {:array, :uuid}

      change manage_relationship(:manage_services, :services, type: :append_and_remove)
      change manage_relationship(:use_resources, :resources, type: :append_and_remove)
    end
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :name, :string, public?: true
    attribute :state, :atom, public?: true
    attribute :status, :atom, public?: true
    attribute :service_id, :uuid, public?: true
  end

  relationships do
    belongs_to :specification, AshNeo4j.Test.Resource.Specification, public?: true
    belongs_to :parent_service, AshNeo4j.Test.Resource.Service, public?: true
    has_many :services, AshNeo4j.Test.Resource.Service
    has_many :resources, AshNeo4j.Test.Resource.Resource
  end
end
