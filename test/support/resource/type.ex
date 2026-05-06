# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Resource.Type do
  @moduledoc false
  use Ash.Resource,
    domain: AshNeo4j.Test.SRM,
    data_layer: AshNeo4j.DataLayer

  alias AshNeo4j.Test.Resource.Money
  alias AshNeo4j.Test.Type.DogKeyword
  alias AshNeo4j.Test.Type.DogMap
  alias AshNeo4j.Test.Type.DogStruct
  alias AshNeo4j.Test.Type.DogTuple
  alias AshNeo4j.Test.Type.DogTypedStruct
  alias AshNeo4j.Test.Type.DogUnion

  actions do
    default_accept :*
    defaults [:read, :create, :destroy]
  end

  attributes do
    uuid_primary_key :uuid
    attribute :array_atom, {:array, :atom}, public?: true
    attribute :array_binary, {:array, :binary}, public?: true
    attribute :array_boolean, {:array, :boolean}, public?: true
    attribute :array_integer, {:array, :integer}, public?: true
    attribute :array_string, {:array, :string}, public?: true
    attribute :array_map, {:array, DogMap}, public?: true
    attribute :array_struct, {:array, DogStruct}, public?: true
    attribute :array_typed_struct, {:array, DogTypedStruct}, public?: true

    attribute :atom, :atom do
      public? true
      default :a
      constraints one_of: [:a, :b]
    end

    attribute :binary, :binary, public?: true
    attribute :boolean, :boolean, public?: true
    attribute :ci_string, :ci_string, public?: true
    attribute :date, :date, public?: true
    attribute :datetime, :datetime, public?: true
    attribute :decimal, :decimal, public?: true
    attribute :duration, :duration, public?: true
    attribute :float, :float, public?: true
    attribute :function, :function, public?: true
    attribute :integer, :integer, public?: true
    attribute :json_string, :string, public?: true
    attribute :keyword, DogKeyword, public?: true
    attribute :map, DogMap, public?: true
    attribute :module, :module, public?: true
    attribute :money, Money, public?: true
    attribute :array_money, {:array, Money}, public?: true
    attribute :naive_datetime, :naive_datetime, public?: true
    attribute :regex, :struct, public?: true
    attribute :string, :string, public?: true
    attribute :struct, DogStruct, public?: true
    attribute :time, :time, public?: true
    attribute :time_usec, :time_usec, public?: true
    attribute :tuple, DogTuple, public?: true
    attribute :typed_struct, DogTypedStruct, public?: true
    attribute :union, DogUnion, public?: true
    attribute :url_encoded_binary, :url_encoded_binary, public?: true
    attribute :utc_datetime_usec, :utc_datetime_usec, public?: true
    attribute :uuid4, :uuid, public?: true
    attribute :uuid7, :uuid_v7, public?: true
  end
end
