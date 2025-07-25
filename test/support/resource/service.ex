defmodule AshNeo4j.Test.Resource.Service do
  @moduledoc false
  use Ash.Resource,
    domain: AshNeo4j.Test.Domain,
    data_layer: AshNeo4j.DataLayer

  neo4j do
    label :InternalService

    relate [
      {:specification, :SPECIFIES, :incoming},
      {:parent_service, :MANAGES, :incoming},
      {:services, :MANAGES, :outgoing},
      {:resources, :USES, :outgoing},
      {:event, :FIRED, :outgoing}
    ]

    skip([:service_id, :parent_service_id])
    translate id: :uuid
  end

  actions do
    defaults [:destroy]

    read :read do
      primary? true
    end

    create :create do
      primary? true
      accept [:name]
      argument :specified_by, :uuid

      change manage_relationship(:specified_by, :specification, type: :append_and_remove)
    end

    update :update do
      primary? true
      require_atomic? false
      argument :manage_services, {:array, :uuid}
      argument :use_resources, {:array, :uuid}
      argument :fire_event, :uuid

      change manage_relationship(:manage_services, :services, type: :append_and_remove)
      change manage_relationship(:use_resources, :resources, type: :append_and_remove)
      change manage_relationship(:fire_event, :event, type: :append_and_remove)
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
    has_one :event, AshNeo4j.Test.Resource.Event
  end

  calculations do
    calculate :href,
              :string,
              expr(
                "serviceInventoryManagement/v" <>
                  specification.tmf_version <>
                  "/service/" <>
                  specification.name <>
                  "/" <> id
              ) do
      description "the inventory href of the service"
    end
  end

  preparations do
    prepare build(
              load: [:href, :specification, :services, :resources, :event],
              sort: [id: :asc]
            )
  end
end
