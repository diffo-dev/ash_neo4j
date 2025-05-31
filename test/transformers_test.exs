defmodule AshNeo4j.Transformers.Test do
  use ExUnit.Case, async: false

  describe "Transformers tests" do
    test "label is defaulted" do
      assert AshNeo4j.DataLayer.Info.label(AshNeo4j.Test.Resource.Type) == :Type
    end

    test "translations are added" do
      translation = AshNeo4j.DataLayer.Info.translation(AshNeo4j.Test.Resource.Comment)
      assert Keyword.get(translation, :id) == :uuid
      assert Keyword.get(translation, :title) == :title
    end
  end
end
