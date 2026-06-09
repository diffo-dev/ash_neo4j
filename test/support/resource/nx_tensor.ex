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

  attributes do
    uuid_primary_key :uuid

    # Inferred type, any rank — exercises 1D/2D/3D integer round-trip.
    attribute :t_default, AshNeo4j.Type.NxTensor, public?: true

    # Float, native LIST storage.
    attribute :t_f32, AshNeo4j.Type.NxTensor, public?: true, constraints: [type: :f32]

    # Float, opaque base64 packed storage.
    attribute :t_packed, AshNeo4j.Type.NxTensor, public?: true, constraints: [store: :packed, type: :f32]
  end
end
