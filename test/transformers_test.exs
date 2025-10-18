# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Transformers do
  @moduledoc false
  use ExUnit.Case

  describe "Transformers tests" do
    test "label is defaulted" do
      assert AshNeo4j.DataLayer.Info.label(AshNeo4j.Test.Resource.Type) == :Type
    end

    test "translations are added" do
      translation = AshNeo4j.DataLayer.Info.translation(AshNeo4j.Test.Resource.Comment)
      assert Keyword.get(translation, :id) == :uuid
      assert Keyword.get(translation, :title) == :title
    end

    test "relationship_attributes are added" do
      relationship_attributes = AshNeo4j.DataLayer.Info.relationship_attributes(AshNeo4j.Test.Resource.Comment)
      assert Keyword.get(relationship_attributes, :post_id) == :post
    end
  end
end
