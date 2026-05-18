# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Resource.CrossDomainBase do
  @moduledoc false

  # Fragment that declares belongs_to :blueprint where Blueprint is in a different
  # Ash domain (Provider vs SRM). Tests that enrichments resolve source attributes
  # across domain boundaries.
  use Spark.Dsl.Fragment,
    of: Ash.Resource,
    data_layer: AshNeo4j.DataLayer

  neo4j do
    label :CrossDomainType
    relate [{:blueprint, :BLUEPRINTED_BY, :outgoing, :Blueprint}]
  end

  actions do
    default_accept :*
    defaults [:read, :destroy]

    create :create do
      primary? true
      argument :blueprinted_by, :uuid
      change manage_relationship(:blueprinted_by, :blueprint, type: :append_and_remove)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  relationships do
    belongs_to :blueprint, AshNeo4j.Test.Resource.Blueprint, public?: true
  end
end
