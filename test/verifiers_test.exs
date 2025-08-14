defmodule AshNeo4j.Test.Verifiers do
  @moduledoc false

  use ExUnit.Case, async: false

  describe "Verifiers tests" do
    test "label: invalid label" do
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

    test "relate: edge label style" do
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
                         relate [{:resources, :uses, :outgoing, :Resource}]
                         translate id: :uuid
                       end

                       attributes do
                         uuid_primary_key :id, writable?: true
                         attribute :name, :string, public?: true
                         attribute :resource_id, :uuid, public?: true
                       end

                       relationships do
                         has_many :resources, AshNeo4j.Test.Resource.Resource
                       end
                     end
                   end
    end

    test "relate: mismatched relationships" do
      assert_raise Spark.Error.DslError,
                   ~r/relate: relate and relationships have different number of entries/,
                   fn ->
                     defmodule MismatchedRelationships do
                       @moduledoc false
                       use Ash.Resource,
                         domain: AshNeo4j.Test.Domain,
                         data_layer: AshNeo4j.DataLayer

                       neo4j do
                         label :Resource
                         relate [{:resourceful, :USES, :outgoing, :MismatchedRelationships}]
                         translate id: :uuid
                       end

                       attributes do
                         uuid_primary_key :id, writable?: true
                         attribute :name, :string, public?: true
                         attribute :resource_id, :uuid, public?: true
                         attribute :mismatched_relationships_id, :uuid, public?: true
                       end

                       relationships do
                         has_many :resources, MismatchedRelationships
                         belongs_to :resource, MismatchedRelationships, public?: true
                       end
                     end
                   end
    end

    test "relate: invalid edge direction" do
      assert_raise Spark.Error.DslError,
                   ~r/relate: edge directions must be :incoming or :outgoing, invalid edge directions: forwards/,
                   fn ->
                     defmodule RelateInvalidEdgeDirection do
                       @moduledoc false
                       use Ash.Resource,
                         domain: AshNeo4j.Test.Domain,
                         data_layer: AshNeo4j.DataLayer

                       neo4j do
                         label :Resource
                         relate [{:resources, :USES, :forwards, :RelateInvalidEdgeDirection}]
                         translate id: :uuid
                       end

                       attributes do
                         uuid_primary_key :id, writable?: true
                         attribute :name, :string, public?: true
                         attribute :resource_id, :uuid, public?: true
                         attribute :relate_invalid_edge_direction_id, :uuid, public?: true
                       end

                       relationships do
                         has_many :resources, RelateInvalidEdgeDirection
                       end
                     end
                   end
    end

    test "relate: destination label style" do
      assert_raise Spark.Error.DslError,
                   ~r/relate: destination labels must be PascalCase, invalid destination labels: relateInvalidDestinationLabel/,
                   fn ->
                     defmodule RelateInvalidDestinationLabel do
                       @moduledoc false
                       use Ash.Resource,
                         domain: AshNeo4j.Test.Domain,
                         data_layer: AshNeo4j.DataLayer

                       neo4j do
                         label :Resource
                         relate [{:resources, :USES, :outgoing, :relateInvalidDestinationLabel}]
                         translate id: :uuid
                       end

                       attributes do
                         uuid_primary_key :id, writable?: true
                         attribute :name, :string, public?: true
                         attribute :resource_id, :uuid, public?: true
                         attribute :relate_invalid_destination_label_id, :uuid, public?: true
                       end

                       relationships do
                         has_many :resources, RelateInvalidDestinationLabel
                       end
                     end
                   end
    end

    test "guard: edge label style" do
      assert_raise Spark.Error.DslError,
                   ~r/guard: edge labels must be upper case and may have an underscore, invalid edge labels: \[:specifies\]/,
                   fn ->
                     defmodule GuardInvalidEdgeLabel do
                       @moduledoc false
                       use Ash.Resource,
                         domain: AshNeo4j.Test.Domain,
                         data_layer: AshNeo4j.DataLayer

                       neo4j do
                         guard [{:specifies, :outgoing, :Resource}]
                       end

                       attributes do
                         uuid_primary_key :uuid, writable?: true
                       end
                     end
                   end
    end

    test "guard: invalid edge direction" do
      assert_raise Spark.Error.DslError,
                   ~r/guard: invalid edge directions: \[:forwards\]/,
                   fn ->
                     defmodule GuardInvalidEdgeDirection do
                       @moduledoc false
                       use Ash.Resource,
                         domain: AshNeo4j.Test.Domain,
                         data_layer: AshNeo4j.DataLayer

                       neo4j do
                         guard [{:SPECIFIES, :forwards, :Resource}]
                       end

                       attributes do
                         uuid_primary_key :uuid, writable?: true
                       end
                     end
                   end
    end

    test "guard: destination label style" do
      assert_raise Spark.Error.DslError,
                   ~r/guard: destination labels must be PascalCase, invalid destination labels: \[:resource\]/,
                   fn ->
                     defmodule GuardInvalidDestinationLabel do
                       @moduledoc false
                       use Ash.Resource,
                         domain: AshNeo4j.Test.Domain,
                         data_layer: AshNeo4j.DataLayer

                       neo4j do
                         guard [{:SPECIFIES, :outgoing, :resource}]
                       end

                       attributes do
                         uuid_primary_key :uuid, writable?: true
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
