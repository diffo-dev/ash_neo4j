defmodule AshNeo4j.Test.Resource.Chain do
  @moduledoc false
  use Ash.Resource,
    domain: AshNeo4j.Test.Domain,
    data_layer: AshNeo4j.DataLayer

  neo4j do
    label :Chain

    relate [
      {:head, :HEAD_TO_TAIL, :incoming},
      {:tail, :HEAD_TO_TAIL, :outgoing}
    ]

    translate id: :uuid
  end

  actions do
    default_accept :*
    defaults [:destroy]

    read :read do
      primary? true
    end

    create :create do
      primary? true
      accept [:name]
      argument :head_id, :uuid
      argument :tail_id, :uuid
      change manage_relationship :head_id, :head, type: :append_and_remove
      change manage_relationship :tail_id, :tail, type: :append_and_remove
    end

    update :update do
      primary? true
      accept [:name]
      argument :head_id, :uuid
      argument :tail_id, :uuid
      change manage_relationship :head_id, :head, type: :append_and_remove
      change manage_relationship :tail_id, :tail, type: :append_and_remove
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :tail_id, :uuid
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :head, AshNeo4j.Test.Resource.Chain, allow_nil?: true, public?: true, source_attribute: :head_id
    belongs_to :tail, AshNeo4j.Test.Resource.Chain, allow_nil?: true, public?: true, source_attribute: :tail_id
  end

  preparations do
    prepare build sort: [inserted_at: :desc], load: [:head_id, :tail_id]
  end
end
