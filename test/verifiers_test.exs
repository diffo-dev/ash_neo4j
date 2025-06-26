defmodule AshNeo4j.Test.Verifiers do
  @moduledoc false

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
      assert_raise Spark.Error.DslError,
                   ~r/relate: edge labels must be upper case and may have an underscore, invalid edge labels: uses/,
                   fn ->
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
                       end
                     end
                   end
    end

    test "mismatched relationship names" do
      assert_raise Spark.Error.DslError,
                   ~r/relate: relationship names must match the name of a relationship, mismatched relationship names: resourced/,
                   fn ->
                     defmodule MismatchedRelationshipNames do
                       @moduledoc false
                       use Ash.Resource,
                         domain: AshNeo4j.Test.Domain,
                         data_layer: AshNeo4j.DataLayer

                       neo4j do
                         label :Resource
                         relate [{:resourced, :USES, :forwards}]
                         translate id: :uuid
                       end

                       attributes do
                         uuid_primary_key :id, writable?: true
                         attribute :name, :string, public?: true
                         attribute :resource_id, :uuid, public?: true
                       end

                       relationships do
                         has_many :resources, MismatchedRelationshipNames
                       end
                     end
                   end
    end

    test "edge direction" do
      assert_raise Spark.Error.DslError,
                   ~r/relate: edge directions must be :incoming or :outgoing, invalid edge directions: forwards/,
                   fn ->
                     defmodule InvalidEdgeDirection do
                       @moduledoc false
                       use Ash.Resource,
                         domain: AshNeo4j.Test.Domain,
                         data_layer: AshNeo4j.DataLayer

                       neo4j do
                         label :Resource
                         relate [{:resources, :USES, :forwards}]
                         translate id: :uuid
                       end

                       attributes do
                         uuid_primary_key :id, writable?: true
                         attribute :name, :string, public?: true
                         attribute :resource_id, :uuid, public?: true
                       end

                       relationships do
                         has_many :resources, InvalidEdgeDirection
                       end
                     end
                   end
    end

    test "mismatched relationships" do
      assert_raise Spark.Error.DslError,
                   ~r/relate: relate must have an entry for each relationship/,
                   fn ->
                     defmodule MismatchedRelationships do
                       @moduledoc false
                       use Ash.Resource,
                         domain: AshNeo4j.Test.Domain,
                         data_layer: AshNeo4j.DataLayer

                       neo4j do
                         label :Resource
                         relate [{:resources, :USES, :forwards}]
                         translate id: :uuid
                       end

                       attributes do
                         uuid_primary_key :id, writable?: true
                         attribute :name, :string, public?: true
                         attribute :resource_id, :uuid, public?: true
                       end

                       relationships do
                         has_many :resources, MismatchedRelationships
                         belongs_to :resource, MismatchedRelationships, public?: true
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
