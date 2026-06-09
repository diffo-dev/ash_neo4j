# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Resource.NxTensor do
  @moduledoc false
  use Ash.Resource,
    domain: AshNeo4j.Test.SRM,
    data_layer: AshNeo4j.DataLayer

  neo4j do
    label :NxTensor
  end

  actions do
    default_accept :*
    defaults [:read, :create, :destroy]
  end

  # Shape is a required constraint, so each attribute is a fixed shape.
  attributes do
    uuid_primary_key :uuid

    attribute :t_1d, AshNeo4j.Type.NxTensor, public?: true, constraints: [type: :s64, shape: [3]]
    attribute :t_2d, AshNeo4j.Type.NxTensor, public?: true, constraints: [type: :s64, shape: [2, 2]]
    attribute :t_3d, AshNeo4j.Type.NxTensor, public?: true, constraints: [type: :s64, shape: [2, 2, 2]]

    # Float, native LIST storage.
    attribute :t_f32, AshNeo4j.Type.NxTensor, public?: true, constraints: [type: :f32, shape: [2, 2]]

    # Float, opaque base64 packed storage.
    attribute :t_packed, AshNeo4j.Type.NxTensor,
      public?: true,
      constraints: [store: :packed, type: :f32, shape: [1, 2]]

    # A 9x9 Sudoku grid (u8).
    attribute :sudoku, AshNeo4j.Type.NxTensor, public?: true, constraints: [type: :u8, shape: [9, 9]]
  end
end
