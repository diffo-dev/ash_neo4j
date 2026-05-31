# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Resource.Thing do
  @moduledoc false
  use Ash.Resource,
    domain: AshNeo4j.Test.SRM,
    extensions: [AshStateMachine],
    data_layer: AshNeo4j.DataLayer

  neo4j do
    label :Thing

    relate [
      {:category, :CATEGORISED_BY, :outgoing, :ThingCategory},
      {:tags, :HAS, :outgoing, :ThingTag},
      {:notes, :HAS, :outgoing, :ThingNote}
    ]
  end

  state_machine do
    initial_states([:initial])
    default_initial_state(:initial)
    state_attribute(:state)

    transitions do
      transition(:activate, from: :initial, to: [:active])
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      argument :category_id, :uuid
      argument :tags, {:array, :uuid}
      argument :notes, {:array, :uuid}

      change manage_relationship(:category_id, :category, type: :append)
      change manage_relationship(:tags, type: :append)
      change manage_relationship(:notes, type: :append)
    end

    update :activate do
      change transition_state(:active)
    end
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :name, :string, public?: true
  end

  relationships do
    belongs_to :category, AshNeo4j.Test.Resource.ThingCategory, public?: true
    has_many :tags, AshNeo4j.Test.Resource.ThingTag, destination_attribute: :thing_id, public?: true
    has_many :notes, AshNeo4j.Test.Resource.ThingNote, destination_attribute: :thing_id, public?: true
  end
end
