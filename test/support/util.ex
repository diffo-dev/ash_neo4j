# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Util do
  @moduledoc false
  use ExUnit.Case

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
end
