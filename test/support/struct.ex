# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Struct do
  use Ash.Type
  @moduledoc false

  defstruct a: :a, b: false, d: Decimal.new("4.2"), f: 1.2, i: 0, n: nil, s: "Hello"

  @impl Ash.Type
  def storage_type, do: :map

  @impl Ash.Type
  def cast_input(nil, _constraints), do: {:ok, nil}

  def cast_input(value, _constraints) when is_map(value) do
    {:ok, struct(__MODULE__, value)}
  end

  @impl Ash.Type
  def cast_stored(nil, _constraints), do: {:ok, nil}

  def cast_stored(value, _constraints) when is_map(value) do
    {:ok, struct(__MODULE__, value)}
  end

  @impl Ash.Type
  def dump_to_native(nil, _constraints), do: {:ok, nil}

  def dump_to_native(value, _constraints) do
    {:ok, Map.from_struct(value)}
  end

  defimpl Jason.Encoder do
    def encode(value, opts) do
      Jason.Encode.map(Map.from_struct(value), opts)
    end
  end
end
