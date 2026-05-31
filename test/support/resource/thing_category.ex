# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Resource.ThingCategory do
  @moduledoc false
  use Ash.Resource,
    domain: AshNeo4j.Test.SRM,
    data_layer: AshNeo4j.DataLayer

  neo4j do
    label :ThingCategory
  end

  actions do
    default_accept :*
    defaults [:read, :create, :destroy]
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :name, :string, public?: true
  end
end
