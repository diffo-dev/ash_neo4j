# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Transformers do
  @moduledoc false
  use ExUnit.Case
  alias AshNeo4j.Resource.Info, as: ResourceInfo

  describe "Transformers tests" do
    test "label is defaulted" do
      assert ResourceInfo.label(AshNeo4j.Test.Resource.Type) == :Type
    end

    test "translations are added" do
      translations = ResourceInfo.translations(AshNeo4j.Test.Resource.Comment)
      assert Keyword.get(translations, :id) == :uuid
      assert Keyword.get(translations, :title) == :title
    end

    test "explicit translations are left alone" do
      translations = ResourceInfo.translations(AshNeo4j.Test.Resource.Specification)
      assert Keyword.get(translations, :major_version) == :versionMajor
      assert Keyword.get(translations, :minor_version) == :versionMinor
      assert Keyword.get(translations, :patch_version) == :versionPatch
    end

    test "implicit translations are camelCased" do
      translations = ResourceInfo.translations(AshNeo4j.Test.Resource.Event)
      assert Keyword.get(translations, :inserted_at) == :insertedAt
      assert Keyword.get(translations, :updated_at) == :updatedAt
    end

    test "relationship_attributes are added" do
      relationship_attributes = ResourceInfo.relationship_attributes(AshNeo4j.Test.Resource.Comment)
      assert Keyword.get(relationship_attributes, :post_id) == :post
    end

    test "author has correct translations" do
      translations =
        ResourceInfo.translations(AshNeo4j.Test.Resource.Author)

      assert Keyword.get(translations, :id) == :uuid
      assert Keyword.get(translations, :name) == :name
    end
  end
end
