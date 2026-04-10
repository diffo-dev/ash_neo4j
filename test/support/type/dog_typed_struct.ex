# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Type.DogTypedStruct do
  @moduledoc false

  use Ash.TypedStruct

  typed_struct do
    field :name, :string, allow_nil?: false
    field :age, :integer, constraints: [min: 0]
    field :breed, :atom, default: nil
  end
end
