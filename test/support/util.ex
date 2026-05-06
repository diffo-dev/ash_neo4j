# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Util do
  @moduledoc false
  use ExUnit.Case
  import ExUnit.CaptureIO

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

  def init_constraints(type) do
    {:ok, constraints} = Ash.Type.init(type, type.subtype_constraints())
    constraints
  end
end
