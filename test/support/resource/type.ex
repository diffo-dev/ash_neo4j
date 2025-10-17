# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Resource.Type do
  @moduledoc false
  use Ash.Resource,
    domain: AshNeo4j.Test.Domain,
    data_layer: AshNeo4j.DataLayer

  actions do
    default_accept :*
    defaults [:read, :create, :destroy]
  end

  attributes do
    uuid_primary_key :uuid
    attribute :array_atom, {:array, :atom}, public?: true
    attribute :array_boolean, {:array, :boolean}, public?: true
    attribute :array_integer, {:array, :integer}, public?: true
    attribute :array_string, {:array, :string}, public?: true
    attribute :array_map, {:array, :map}, public?: true
    attribute :array_struct, {:array, :struct}, public?: true
    attribute :array_term, {:array, :term}, public?: true

    attribute :atom, :atom do
      public? true
      default :a
      constraints one_of: [:a, :b]
    end

    attribute :binary, :binary, public?: true
    attribute :boolean, :boolean, public?: true

    attribute :ci_string, :ci_string do
      public? true
      constraints casing: :upper
    end

    attribute :date, :date, public?: true
    attribute :datetime, :datetime, public?: true
    attribute :decimal, :decimal, public?: true
    attribute :duration, :duration, public?: true
    attribute :float, :float, public?: true
    attribute :function, :function, public?: true
    attribute :integer, :integer, public?: true
    attribute :json_string, :string, public?: true

    attribute :keyword, :keyword do
      public? true

      constraints fields: [
                    a: [type: :atom],
                    s: [type: :string]
                  ]
    end

    attribute :map, :map, public?: true
    attribute :mapset, :struct, public?: true
    attribute :module, :module, public?: true
    attribute :money, AshNeo4j.Test.Resource.Money, public?: true
    attribute :array_money, {:array, AshNeo4j.Test.Resource.Money}, public?: true
    attribute :naive_datetime, :naive_datetime, public?: true
    attribute :regex, :struct, public?: true
    attribute :string, :string, public?: true
    attribute :struct, :struct, public?: true
    attribute :struct_in_struct, :struct, public?: true
    attribute :term, :term, public?: true
    attribute :time, :time, public?: true
    attribute :time_usec, :time_usec, public?: true

    attribute :tuple, :tuple do
      public? true

      constraints fields: [
                    a: [type: :atom],
                    i: [type: :integer],
                    b: [type: :boolean]
                  ]
    end

    attribute :url, :url_encoded_binary, public?: true
    attribute :utc_datetime_usec, :utc_datetime_usec, public?: true
  end
end
