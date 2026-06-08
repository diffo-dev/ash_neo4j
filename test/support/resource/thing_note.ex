# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Resource.ThingNote do
  @moduledoc false
  use Ash.Resource,
    domain: AshNeo4j.Test.SRM,
    data_layer: AshNeo4j.DataLayer

  neo4j do
    label :ThingNote
    relate [{:thing, :HAS, :incoming, :Thing}]
    skip [:thing_id]
  end

  actions do
    default_accept :*
    defaults [:read, :create, :destroy, update: :*]
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :body, :string, public?: true
    attribute :thing_id, :uuid, public?: true

    attribute :embedding, AshNeo4j.Types.Vector,
      public?: true,
      constraints: [element_type: :float32, dimensions: 3]
  end

  relationships do
    belongs_to :thing, AshNeo4j.Test.Resource.Thing, public?: true
  end
end
