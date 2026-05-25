# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Functions.StDistanceInMetersTest do
  @moduledoc """
  `st_distance_in_meters` — alias for `st_distance`. Behaves identically;
  exists for API parity with ash_geo.
  """
  use ExUnit.Case, async: true

  require Ash.Query

  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Functions.StDistanceInMeters
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Place
  alias Bolty.Types.Point

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  test "evaluate/1 delegates to st_distance" do
    sydney = Point.create(:wgs_84, 151.2093, -33.8688)
    melbourne = Point.create(:wgs_84, 144.9631, -37.8136)
    {:known, meters} = StDistanceInMeters.evaluate(%{arguments: [sydney, melbourne]})
    assert_in_delta meters, 713_000, 5_000
  end

  test "pushes down in filter comparison, same as st_distance" do
    sydney_place = Place |> Ash.create!(%{name: "Sydney", location: Point.create(:wgs_84, 151.2093, -33.8688)})
    _melbourne = Place |> Ash.create!(%{name: "Melbourne", location: Point.create(:wgs_84, 144.9631, -37.8136)})

    near_sydney = Point.create(:wgs_84, 151.2, -33.85)
    threshold = 50_000.0

    {:ok, results} =
      Place
      |> Ash.Query.filter(st_distance_in_meters(location, ^near_sydney) < ^threshold)
      |> Ash.read()

    ids = Enum.map(results, & &1.id)
    assert sydney_place.id in ids
    assert length(results) == 1
  end
end
