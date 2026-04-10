# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Util do
  @moduledoc false
  use ExUnit.Case
  import ExUnit.CaptureIO
  alias AshNeo4j.Test.Type.DogMap
  alias AshNeo4j.Test.Type.DogStruct
  alias AshNeo4j.Test.Type.DogTypedStruct

  def check_enrichment(resource, struct_name, module, name, value)
      when is_struct(resource) and is_atom(struct_name) and is_nil(module) and is_atom(name) do
    refute Map.get(resource, struct_name)
    assert Map.get(resource, name) == value
  end

  def check_enrichment(resource, struct_name, module, name, value)
      when is_struct(resource) and is_atom(struct_name) and is_atom(module) and is_atom(name) do
    assert is_struct(Map.get(resource, struct_name), module)
    assert Map.get(resource, name) == value
  end

  def assert_compile_time_warning(module, message, fun) when is_bitstring(message) do
    output = capture_io(:stderr, fun)
    assert output =~ String.trim_leading("#{module}", "Elixir.")
    assert output =~ message
  end

  @spec durations_equal(Duration.t(), Duration.t()) :: boolean()
  def durations_equal(%Duration{} = d1, %Duration{} = d2) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    dt1 = DateTime.shift(now, d1)
    dt2 = DateTime.shift(now, d2)
    DateTime.compare(dt1, dt2) == :eq
  end

  @fields [
    name: [
      allow_nil?: false,
      constraints: [trim?: true, allow_empty?: false],
      type: Ash.Type.String
    ],
    age: [allow_nil?: true, constraints: [min: 0], type: Ash.Type.Integer],
    breed: [
      allow_nil?: true,
      constraints: [unsafe_to_atom?: false],
      type: Ash.Type.Atom
    ]
  ]

  def constraints(DogMap), do: [fields: @fields, preserve_nil_values?: false]

  def constraints(DogStruct), do: [fields: @fields, instance_of: DogStruct, preserve_nil_values?: false]

  def constraints(DogTypedStruct), do: [fields: @fields, instance_of: DogTypedStruct, preserve_nil_values?: false]
end
