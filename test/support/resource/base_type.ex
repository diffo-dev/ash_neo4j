# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Resource.BaseType do
  @moduledoc false

  # Fragment that declares belongs_to :specification with an explicit edge label.
  # Specification has no reverse relationship back (too many instances to load).
  # This mirrors the BaseInstance → Specification setup in diffo.
  use Spark.Dsl.Fragment,
    of: Ash.Resource,
    data_layer: AshNeo4j.DataLayer

  neo4j do
    label :Type
    relate [{:specification, :SPECIFIED_BY, :outgoing, :Specification}]
  end

  actions do
    default_accept :*
    defaults [:read, :destroy]

    create :create do
      primary? true
      argument :specified_by, :uuid
      change manage_relationship(:specified_by, :specification, type: :append_and_remove)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  relationships do
    belongs_to :specification, AshNeo4j.Test.Resource.Specification, public?: true
  end
end
