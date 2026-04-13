# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Verifiers do
  @moduledoc false

  use ExUnit.Case, async: false
  alias AshNeo4j.Test.Util

  describe "Verifiers tests" do
    test "label: invalid label warns DslError on compilation" do
      Util.assert_compile_time_warning(
        Spark.Error.DslError,
        "label: neo4j label must be PascalCase",
        fn ->
          defmodule InvalidLabel do
            use Ash.Resource,
              domain: AshNeo4j.Test.SRM,
              data_layer: AshNeo4j.DataLayer

            neo4j do
              label :comment
            end

            attributes do
              uuid_primary_key :id
              attribute :title, :string, public?: true
            end
          end
        end
      )
    end

    test "relate: edge label style warns DslError on compilation" do
      Util.assert_compile_time_warning(
        Spark.Error.DslError,
        "relate: edge labels must be upper case and may have an underscore, invalid edge labels: uses",
        fn ->
          defmodule InvalidEdgeLabel do
            @moduledoc false
            use Ash.Resource,
              domain: AshNeo4j.Test.SRM,
              data_layer: AshNeo4j.DataLayer

            neo4j do
              label :Resource
              relate [{:resources, :uses, :outgoing, :Resource}]
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
      )
    end

    test "relate: mismatched relationships" do
      Util.assert_compile_time_warning(
        Spark.Error.DslError,
        "relate: relate and relationships have different number of entries",
        fn ->
          defmodule MismatchedRelationships do
            @moduledoc false
            use Ash.Resource,
              domain: AshNeo4j.Test.SRM,
              data_layer: AshNeo4j.DataLayer

            neo4j do
              label :Resource
              relate [{:resourceful, :USES, :outgoing, :MismatchedRelationships}]
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
      )
    end

    test "relate: invalid edge direction" do
      Util.assert_compile_time_warning(
        Spark.Error.DslError,
        "relate: edge directions must be :incoming or :outgoing, invalid edge directions: forwards",
        fn ->
          defmodule RelateInvalidEdgeDirection do
            @moduledoc false
            use Ash.Resource,
              domain: AshNeo4j.Test.SRM,
              data_layer: AshNeo4j.DataLayer

            neo4j do
              label :Resource
              relate [{:resources, :USES, :forwards, :RelateInvalidEdgeDirection}]
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
      )
    end

    test "relate: destination label style" do
      Util.assert_compile_time_warning(
        Spark.Error.DslError,
        "relate: destination labels must be PascalCase, invalid destination labels: relateInvalidDestinationLabel",
        fn ->
          defmodule RelateInvalidDestinationLabel do
            @moduledoc false
            use Ash.Resource,
              domain: AshNeo4j.Test.SRM,
              data_layer: AshNeo4j.DataLayer

            neo4j do
              label :Resource
              relate [{:resources, :USES, :outgoing, :relateInvalidDestinationLabel}]
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
      )
    end

    test "guard: edge label style" do
      Util.assert_compile_time_warning(
        Spark.Error.DslError,
        "guard: edge labels must be upper case and may have an underscore, invalid edge labels: \[:specifies\]",
        fn ->
          defmodule GuardInvalidEdgeLabel do
            @moduledoc false
            use Ash.Resource,
              domain: AshNeo4j.Test.SRM,
              data_layer: AshNeo4j.DataLayer

            neo4j do
              guard [{:specifies, :outgoing, :Resource}]
            end

            attributes do
              uuid_primary_key :uuid, writable?: true
            end
          end
        end
      )
    end

    test "guard: invalid edge direction" do
      Util.assert_compile_time_warning(
        Spark.Error.DslError,
        "guard: invalid edge directions: \[:forwards\]",
        fn ->
          defmodule GuardInvalidEdgeDirection do
            @moduledoc false
            use Ash.Resource,
              domain: AshNeo4j.Test.SRM,
              data_layer: AshNeo4j.DataLayer

            neo4j do
              guard [{:SPECIFIES, :forwards, :Resource}]
            end

            attributes do
              uuid_primary_key :uuid, writable?: true
            end
          end
        end
      )
    end

    test "guard: destination label style" do
      Util.assert_compile_time_warning(
        Spark.Error.DslError,
        "guard: destination labels must be PascalCase, invalid destination labels: \[:resource\]",
        fn ->
          defmodule GuardInvalidDestinationLabel do
            @moduledoc false
            use Ash.Resource,
              domain: AshNeo4j.Test.SRM,
              data_layer: AshNeo4j.DataLayer

            neo4j do
              guard [{:SPECIFIES, :outgoing, :resource}]
            end

            attributes do
              uuid_primary_key :uuid, writable?: true
            end
          end
        end
      )
    end

    test "property style - attribute" do
      Util.assert_compile_time_warning(
        Spark.Error.DslError,
        "neo4j: neo4j property names must be camelCase",
        fn ->
          defmodule InvalidStoreProperty do
            @moduledoc false
            use Ash.Resource,
              domain: AshNeo4j.Test.SRM,
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
      )
    end

    test "property style - attribute source" do
      Util.assert_compile_time_warning(
        Spark.Error.DslError,
        "neo4j: neo4j property names must be camelCase",
        fn ->
          defmodule InvalidSourceAttribute do
            @moduledoc false
            use Ash.Resource,
              domain: AshNeo4j.Test.SRM,
              data_layer: AshNeo4j.DataLayer

            neo4j do
              label :Resource
            end

            attributes do
              uuid_primary_key :id, writable?: true
              attribute :name, :string, public?: true, source: :_name
            end
          end
        end
      )
    end

    @tag :verifier
    test "unsupported attribute type" do
      Util.assert_compile_time_warning(
        Spark.Error.DslError,
        "attribute :name requires unsupported type Ash.Type.Term",
        fn ->
          defmodule InvalidAttributeType do
            @moduledoc false
            use Ash.Resource,
              domain: AshNeo4j.Test.SRM,
              data_layer: AshNeo4j.DataLayer

            neo4j do
              label :Resource
            end

            attributes do
              uuid_primary_key :id, writable?: true
              attribute :name, :term, public?: true
            end
          end
        end
      )
    end

    @tag :verifier
    test "unsupported attribute type - within array" do
      Util.assert_compile_time_warning(
        Spark.Error.DslError,
        "attribute :file_array requires unsupported type Ash.Type.File",
        fn ->
          defmodule InvalidAttributeTypeWithinArray do
            @moduledoc false
            use Ash.Resource,
              domain: AshNeo4j.Test.SRM,
              data_layer: AshNeo4j.DataLayer

            neo4j do
              label :Resource
            end

            attributes do
              uuid_primary_key :id, writable?: true
              attribute :file_array, {:array, :file}, public?: true
            end
          end
        end
      )
    end

    @tag :verifier
    test "unsupported attribute type - within typed struct" do
      Util.assert_compile_time_warning(
        Spark.Error.DslError,
        "attribute :typed_struct requires unsupported type Ash.Type.Term",
        fn ->
          defmodule InvalidAttributeWithinTypedStruct do
            @moduledoc false
            use Ash.Resource,
              domain: AshNeo4j.Test.SRM,
              data_layer: AshNeo4j.DataLayer

            neo4j do
              label :Resource
            end

            attributes do
              uuid_primary_key :id, writable?: true
              attribute :typed_struct, AshNeo4j.Test.Type.InvalidTypedStruct, public?: true
            end
          end
        end
      )
    end
  end
end
