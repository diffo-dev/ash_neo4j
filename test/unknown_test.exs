# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.UnknownTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias AshNeo4j.Test.Resource.Party
  alias AshNeo4j.Test.Resource.Place
  alias AshNeo4j.Unknown

  # A stand-in for a future store-native unknown: a different struct type with a
  # `:reason` leaf and no Ash world — exercises the duck-typed nesting.
  defmodule StoreUnknown do
    @moduledoc false
    defstruct [:world, :reason, :context]
  end

  describe "new/3 and shape" do
    test "stamps world, reason and context" do
      u = Unknown.new(Place, :reached_unresolved, %{label: :Foo})
      assert %Unknown{world: Place, reason: :reached_unresolved, context: %{label: :Foo}} = u
    end

    test "context defaults to an empty map" do
      assert Unknown.new(Place, :no_concrete_world).context == %{}
    end
  end

  describe "unknown?/1" do
    test "true for an Unknown, false otherwise" do
      assert Unknown.unknown?(Unknown.new(Place, :x))
      refute Unknown.unknown?(nil)
      refute Unknown.unknown?(:x)
      refute Unknown.unknown?(%{world: Place})
    end
  end

  describe "domain/1" do
    test "derives the Ash domain from the world resource" do
      assert Unknown.domain(Unknown.new(Place, :x)) == Ash.Resource.Info.domain(Place)
      refute is_nil(Unknown.domain(Unknown.new(Place, :x)))
    end

    test "nil when there is no world" do
      assert Unknown.domain(Unknown.new(nil, :x)) == nil
    end
  end

  describe "root_reason/1" do
    test "a single-layer reason is its own root" do
      assert Unknown.root_reason(Unknown.new(Place, :reached_unresolved)) == :reached_unresolved
    end

    test "walks nested AshNeo4j.Unknown layers to the leaf atom" do
      inner = Unknown.new(Party, :no_target)
      outer = Unknown.new(Place, inner)
      assert Unknown.root_reason(outer) == :no_target
    end

    test "walks through a foreign nested unknown (store-native leaf)" do
      store = %StoreUnknown{world: nil, reason: :indeterminate}
      u = Unknown.new(Place, store)
      assert Unknown.root_reason(u) == :indeterminate
    end
  end

  describe "world_chain/1" do
    test "single layer is a one-element chain" do
      assert Unknown.world_chain(Unknown.new(Place, :x)) == [Place]
    end

    test "outermost-first across nested Ash layers" do
      inner = Unknown.new(Party, :no_target)
      outer = Unknown.new(Place, inner)
      assert Unknown.world_chain(outer) == [Place, Party]
    end

    test "a worldless (store-native) layer contributes nothing" do
      store = %StoreUnknown{world: nil, reason: :indeterminate}
      u = Unknown.new(Place, store)
      assert Unknown.world_chain(u) == [Place]
    end
  end
end
