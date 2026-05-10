# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Resource.Post do
  @moduledoc false
  use Ash.Resource,
    domain: AshNeo4j.Test.SRM,
    data_layer: AshNeo4j.DataLayer

  neo4j do
    label :Post

    relate [
      {:comments, :BELONGS_TO, :incoming, :Comment},
      {:tags, :TAGS, :incoming, :Tag},
      {:author, :WROTE, :incoming, :Author}
    ]

    skip [:tag_id]
  end

  actions do
    default_accept :*
    defaults [:read, :destroy]

    create :create do
      primary? true
      argument :written_by, :uuid

      change manage_relationship(:written_by, :author, type: :append_and_remove)
    end

    update :update do
      primary? true
      require_atomic? false
      argument :add_comments, {:array, :uuid}
      accept [:score]

      change manage_relationship(:add_comments, :comments, type: :append_and_remove)
    end

    update :unrelate do
      require_atomic? false
      argument :remove_comments, {:array, :uuid}
      accept [:score]

      change manage_relationship(:remove_comments, :comments, type: :remove)
    end

    update :manage_tags do
      require_atomic? false
      argument :tags, {:array, :uuid}

      change manage_relationship(:tags, :tags, type: :append_and_remove)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :score, :integer, public?: true, allow_nil?: true
    attribute :public, :boolean, public?: true
    attribute :unique, :string, public?: true
    attribute :author_id, :uuid, public?: true, allow_nil?: false
    attribute :tag_id, :uuid, public?: true
  end

  identities do
    identity :unique_unique, [:unique]
  end

  relationships do
    has_many :comments, AshNeo4j.Test.Resource.Comment, public?: true
    has_many :tags, AshNeo4j.Test.Resource.Tag, destination_attribute: :post_id, source_attribute: :id, public?: true
    belongs_to :author, AshNeo4j.Test.Resource.Author, public?: true, allow_nil?: false
  end

  aggregates do
    count :comment_count, :comments
    exists :has_comments, :comments
    first :first_comment_title, :comments, field: :title
    list :comment_titles, :comments, field: :title
    list :comment_dogs, :comments, field: :dog
    first :first_comment_dog, :comments, field: :dog

    # Filtered aggregates — used to verify #252 (filters must not be silently dropped).
    first :first_alpha_comment_title, :comments, field: :title do
      filter expr(title == "alpha")
    end

    count :alpha_comment_count, :comments do
      filter expr(title == "alpha")
    end

    exists :has_alpha_comment, :comments do
      filter expr(title == "alpha")
    end

    list :alpha_comment_titles, :comments, field: :title do
      filter expr(title == "alpha")
    end
  end

  preparations do
    prepare build(load: [:comments, :author])
  end
end
