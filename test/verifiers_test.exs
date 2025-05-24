defmodule AshNeo4j.Verifiers.Test do
  use ExUnit.Case, async: false

  describe "Verifiers tests" do
    test "invalid label" do
      assert_raise Spark.Error.DslError, fn ->
        defmodule InvalidLabel do
          @moduledoc false
          use Ash.Resource,
            domain: AshNeo4j.Test.Domain,
            data_layer: AshNeo4j.DataLayer

          neo4j do
            label :comment
            store [:title]
            translate id: :uuid
          end

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
          end
        end
      end
    end

    test "id not translated" do
      assert_raise Spark.Error.DslError, fn ->
        defmodule IdNotTranslated do
          @moduledoc false
          use Ash.Resource,
            domain: AshNeo4j.Test.Domain,
            data_layer: AshNeo4j.DataLayer

          neo4j do
            label :Comment
            store [:title]
          end

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
          end
        end
      end
    end
  end
end
