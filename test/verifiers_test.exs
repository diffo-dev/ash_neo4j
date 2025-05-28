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
          end

          attributes do
            uuid_primary_key :id
            attribute :title, :string, public?: true
          end
        end
      end
    end

    test "edge label style" do
      assert_raise Spark.Error.DslError, fn ->
        defmodule InvalidEdgeLabel do
          @moduledoc false
          use Ash.Resource,
            domain: AshNeo4j.Test.Domain,
            data_layer: AshNeo4j.DataLayer
          neo4j do
            label :Resource
            relate [{:resources, :uses, :outgoing}]
            translate id: :uuid
          end

          attributes do
            uuid_primary_key :id, writable?: true
            attribute :name, :string, public?: true
            attribute :resource_id, :uuid, public?: true
          end

          relationships do
            has_many :resources, InvalidEdgeLabel
            belongs_to :resource, InvalidEdgeLabel, public?: true
          end
        end
      end
    end

    test "property style - attribute" do
      assert_raise Spark.Error.DslError, fn ->
        defmodule InvalidStoreProperty do
          @moduledoc false
          use Ash.Resource,
            domain: AshNeo4j.Test.Domain,
            data_layer: AshNeo4j.DataLayer
          neo4j do
            label :Resource
          end

          attributes do
            uuid_primary_key :id, writable?: true
            attribute :_name, :string, public?: true
          end
        end
      end
    end

    test "property style - translate" do
      assert_raise Spark.Error.DslError, fn ->
        defmodule InvalidTranslateProperty do
          @moduledoc false
          use Ash.Resource,
            domain: AshNeo4j.Test.Domain,
            data_layer: AshNeo4j.DataLayer
          neo4j do
            label :Resource
            translate [:name, :_name]
          end

          attributes do
            uuid_primary_key :id, writable?: true
            attribute :name, :string, public?: true
          end
        end
      end
    end
  end
end
