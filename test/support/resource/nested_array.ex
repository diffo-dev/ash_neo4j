# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Resource.NestedArray do
  @moduledoc false
  use Ash.Resource,
    domain: AshNeo4j.Test.SRM,
    data_layer: AshNeo4j.DataLayer

  alias AshNeo4j.Test.Type.DogMap

  neo4j do
    label :NestedArray
  end

  actions do
    default_accept :*
    defaults [:read, :create, :destroy]
  end

  attributes do
    uuid_primary_key :uuid

    # One representative per TypeClassifier group, two levels deep.
    attribute :aa_integer, {:array, {:array, :integer}}, public?: true
    attribute :aa_float, {:array, {:array, :float}}, public?: true
    attribute :aa_boolean, {:array, {:array, :boolean}}, public?: true
    attribute :aa_string, {:array, {:array, :string}}, public?: true
    attribute :aa_atom, {:array, {:array, :atom}}, public?: true
    attribute :aa_date, {:array, {:array, :date}}, public?: true
    attribute :aa_duration, {:array, {:array, :duration}}, public?: true
    attribute :aa_binary, {:array, {:array, :binary}}, public?: true
    attribute :aa_map, {:array, {:array, DogMap}}, public?: true

    # Three levels deep.
    attribute :aaa_integer, {:array, {:array, {:array, :integer}}}, public?: true
  end
end
