# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.StDwithinTest do
  @moduledoc """
  Tests for `st_dwithin(point, point, ^km)` — the "within distance" predicate
  for SQ-style "POIs near me" queries.
  """
  use ExUnit.Case, async: true

  require Ash.Query

  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Functions.StDwithin
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Place

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  defp geo(lng, lat), do: %Geo.Point{coordinates: {lng, lat}, srid: 4326}

  describe "evaluate/1" do
    test "returns true when within threshold" do
      assert {:known, true} = StDwithin.evaluate(%{arguments: [geo(151.2093, -33.8688), geo(151.2, -33.85), 5_000]})
    end

    test "returns false when beyond threshold" do
      assert {:known, false} = StDwithin.evaluate(%{arguments: [geo(151.2093, -33.8688), geo(144.9631, -37.8136), 5_000]})
    end

    test "boundary is inclusive (PostGIS semantics)" do
      sydney = geo(151.2093, -33.8688)
      assert {:known, true} = StDwithin.evaluate(%{arguments: [sydney, sydney, 0]})
    end

    test "nil arguments yield false" do
      sydney = geo(151.2093, -33.8688)
      assert {:known, false} = StDwithin.evaluate(%{arguments: [nil, sydney, 5_000]})
      assert {:known, false} = StDwithin.evaluate(%{arguments: [sydney, nil, 5_000]})
      assert {:known, false} = StDwithin.evaluate(%{arguments: [sydney, sydney, nil]})
    end
  end

  describe "st_dwithin in Ash.Query.filter" do
    setup do
      sydney = Place |> Ash.create!(%{name: "Sydney CBD", location: geo(151.2093, -33.8688)})
      melbourne = Place |> Ash.create!(%{name: "Melbourne CBD", location: geo(144.9631, -37.8136)})
      {:ok, sydney: sydney, melbourne: melbourne}
    end

    test "finds nearby places", %{sydney: sydney, melbourne: melbourne} do
      customer = geo(151.2, -33.85)

      {:ok, results} =
        Place
        |> Ash.Query.filter(st_dwithin(location, ^customer, 5_000))
        |> Ash.read()

      ids = Enum.map(results, & &1.id)
      assert sydney.id in ids
      refute melbourne.id in ids
    end

    test "broader threshold catches everything in range", %{sydney: sydney, melbourne: melbourne} do
      customer = geo(151.2, -33.85)

      {:ok, results} =
        Place
        |> Ash.Query.filter(st_dwithin(location, ^customer, 1_000_000))
        |> Ash.read()

      ids = Enum.map(results, & &1.id)
      assert sydney.id in ids
      assert melbourne.id in ids
    end

    test "tight threshold returns nothing", %{} do
      far_away = geo(100.0, 0.0)

      {:ok, results} =
        Place
        |> Ash.Query.filter(st_dwithin(location, ^far_away, 100))
        |> Ash.read()

      assert results == []
    end
  end
end
