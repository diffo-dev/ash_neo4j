defmodule AshNeo4j.Test.Resource.Type do
  @moduledoc false
  use Ash.Resource,
    domain: AshNeo4j.Test.Domain,
    data_layer: AshNeo4j.DataLayer

  neo4j do
    label :Type
    store [:uuid, :array_atom, :array_boolean, :array_integer, :array_string, :array_map, :array_term,
      :atom, :binary, :boolean, :ci_string, :date, :datetime, :decimal, :float,:function, :integer,
      :json_string, :keyword, :map, :mapset, :module, :naive_datetime, :regex, :string, :struct, :term,
      :time, :time_usec, :tuple, :url_encoded_binary, :utc_datetime_usec]
  end

  actions do
    default_accept :*
    defaults [:read, :create]
  end

  attributes do
    uuid_primary_key :uuid
    attribute :array_atom, {:array, :atom}, public?: true
    attribute :array_boolean, {:array, :boolean}, public?: true
    attribute :array_integer, {:array, :integer}, public?: true
    attribute :array_string, {:array, :string}, public?: true
    attribute :array_map, {:array, :map}, public?: true
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
    attribute :naive_datetime, :naive_datetime, public?: true
    attribute :regex, :struct, public?: true
    attribute :string, :string, public?: true
    attribute :struct, :struct, public?: true
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
    attribute :url_encoded_binary, :url_encoded_binary, public?: true
    attribute :utc_datetime_usec, :utc_datetime_usec, public?: true
  end
end
