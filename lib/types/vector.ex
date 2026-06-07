# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Types.Vector do
  @moduledoc """
  Ash attribute type for vector embeddings, stored as a Neo4j `LIST<FLOAT>`.

  The Elixir-side value is a plain `[float()]` list, and it is persisted as a
  `LIST<FLOAT>` node property — which is what Neo4j's vector indexes and
  `vector.similarity.cosine/2` operate on. The native Bolt 6.0 `%Bolty.Types.Vector{}`
  type is a *query-parameter* wire type and **cannot be written as a node
  property**, so it is never used for storage. `cast_input/2` and `cast_stored/2`
  still accept a `%Bolty.Types.Vector{}` defensively and unwrap it to `[float()]`.

  > #### Cypher 25 required {: .warning}
  > Vector operations require Cypher 25 (Neo4j ≥ 2025.06) — not Bolt 6.0. With
  > list storage and list query params, similarity search works over Bolt 5.8.
  > This is an AshNeo4j-level requirement — see `AshNeo4j.Cypher.require_cypher25!/0`.

  ## Constraints

    * `:element_type` — `:float32` (default) or `:float64`
    * `:dimensions` — expected number of dimensions; validated on cast when set

  ## Usage

      attribute :embedding, AshNeo4j.Types.Vector,
        constraints: [element_type: :float32, dimensions: 1536]

  See `AshNeo4j.Vector` for index creation helpers and `AshNeo4j.Functions.VectorSimilarity`
  for cosine similarity filtering/sorting.
  """

  use Ash.Type

  @impl Ash.Type
  def storage_type(_constraints), do: :string

  @impl Ash.Type
  def constraints do
    [
      element_type: [
        type: {:one_of, [:float32, :float64]},
        default: :float32,
        doc: "Element precision: `:float32` (IEEE-754 single, default) or `:float64` (IEEE-754 double)."
      ],
      dimensions: [
        type: :pos_integer,
        doc: "Expected number of dimensions. Validated on cast when provided."
      ]
    ]
  end

  @impl Ash.Type
  def apply_constraints(value, constraints) do
    case constraints[:dimensions] do
      nil -> {:ok, value}
      dims when length(value) == dims -> {:ok, value}
      dims -> {:error, "expected #{dims} dimensions, got #{length(value)}"}
    end
  end

  @impl Ash.Type
  def cast_input(nil, _constraints), do: {:ok, nil}

  def cast_input(%Bolty.Types.Vector{data: data}, _constraints) do
    {:ok, Enum.map(data, &(&1 / 1))}
  end

  def cast_input(value, _constraints) when is_list(value) do
    if Enum.all?(value, &is_number/1) do
      {:ok, Enum.map(value, &(&1 / 1))}
    else
      {:error, "expected a list of numbers, got non-numeric element"}
    end
  end

  def cast_input(_, _), do: {:error, "expected a list of floats or a %Bolty.Types.Vector{}"}

  @impl Ash.Type
  def cast_stored(nil, _constraints), do: {:ok, nil}

  def cast_stored(%Bolty.Types.Vector{data: data}, _constraints) do
    {:ok, Enum.map(data, &(&1 / 1))}
  end

  def cast_stored(value, _constraints) when is_list(value) do
    if Enum.all?(value, &is_number/1) do
      {:ok, Enum.map(value, &(&1 / 1))}
    else
      {:error, "unexpected non-numeric element in vector from storage"}
    end
  end

  def cast_stored(_, _), do: {:error, "unexpected value in Neo4j vector property"}

  @impl Ash.Type
  def dump_to_native(nil, _constraints), do: {:ok, nil}

  # Persisted as a LIST<FLOAT>. Neo4j stores embeddings as float lists and
  # `vector.similarity.cosine/2` operates on them directly; the native Bolt 6.0
  # VECTOR type cannot be written as a node property, so it is never used for
  # storage.
  def dump_to_native(value, _constraints) when is_list(value) do
    {:ok, Enum.map(value, &(&1 / 1))}
  end

  def dump_to_native(_, _), do: :error
end
