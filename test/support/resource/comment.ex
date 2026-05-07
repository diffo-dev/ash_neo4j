# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Resource.Comment do
  @moduledoc false
  use Ash.Resource,
    domain: AshNeo4j.Test.SRM,
    data_layer: AshNeo4j.DataLayer

  alias AshNeo4j.Test.Type.DogTypedStruct

  actions do
    default_accept :*
    defaults [:create, :destroy]

    read :read do
      primary? true
    end

    update :update do
      primary? true
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :dog, DogTypedStruct, public?: true, allow_nil?: true
  end

  relationships do
    belongs_to :post, AshNeo4j.Test.Resource.Post, destination_attribute: :id, public?: true
  end

  preparations do
    prepare build(sort: [title: :asc])
  end
end
