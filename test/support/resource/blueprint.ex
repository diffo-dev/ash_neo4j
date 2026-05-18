# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Resource.Blueprint do
  @moduledoc false

  # Destination resource in the Provider domain — no reverse relationship back.
  # Mirrors the Specification → BaseInstance direction in diffo: many instances
  # may reference one Blueprint, so Blueprints do not load their instances.
  use Ash.Resource,
    domain: AshNeo4j.Test.Provider,
    data_layer: AshNeo4j.DataLayer

  actions do
    defaults [:read, :destroy, update: :*]

    create :create do
      primary? true
      accept [:name]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end
end
