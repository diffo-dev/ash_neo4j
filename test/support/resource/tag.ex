# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Resource.Tag do
  @moduledoc false
  use Ash.Resource,
    domain: AshNeo4j.Test.Domain,
    data_layer: AshNeo4j.DataLayer

  neo4j do
    label :Tag
    relate [{:posts, :TAGS, :outgoing, :Post}]
    skip [:post_id]
  end

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
    attribute :value, :string, public?: true
    attribute :post_id, :uuid
  end

  relationships do
    has_many :posts, AshNeo4j.Test.Resource.Post, destination_attribute: :tag_id, source_attribute: :id, public?: true
  end
end
