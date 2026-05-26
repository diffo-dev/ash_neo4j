# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.ShowNeo4jTest do
  @moduledoc """
  Tests tagged `:show_neo4j` build spatial Place nodes in the **real**
  Neo4j database (no sandbox, no rollback) so the nodes can be inspected
  via the Neo4j browser afterwards.

  Each test prints the Ash-side record and a raw Cypher dump of the
  on-disk node properties — including the `<prop>.bbSW` / `<prop>.bbNE`
  bbox companion properties that the data layer writes alongside each
  spatial vertex array.

  Run with:

      mix test --only show_neo4j

  Excluded from default test runs.

  Useful Cypher snippets to paste into Neo4j browser after running:

      // All Places created by this test
      MATCH (n:SRM:Place) RETURN n

      // The showcase node with every spatial type populated
      MATCH (n:SRM:Place {name: 'Spatial showcase'}) RETURN n

      // Inspect raw property keys including the dotted bbox companions
      MATCH (n:SRM:Place {name: 'Spatial showcase'}) RETURN keys(n) AS props

      // Bounding-box prefilter via the indexed scalar companions
      MATCH (n:SRM:Place)
      WHERE n.`path.bbSW` IS NOT NULL
        AND point.withinBBox(
          point({longitude: 151.25, latitude: -33.7}),
          n.`path.bbSW`,
          n.`path.bbNE`
        )
      RETURN n.name, n.path

  Clean up afterwards with:

      MATCH (n:SRM:Place) DETACH DELETE n
  """
  use ExUnit.Case, async: false

  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Test.Resource.Place
  alias AshNeo4j.Type.Box
  alias AshNeo4j.Type.LineString
  alias AshNeo4j.Type.MultiBox
  alias AshNeo4j.Type.MultiPoint
  # Bolty.Types.Point retained because Box.sw/ne, LineString.vertices,
  # MultiPoint.points and MultiBox.boxes' Box internals are still held as
  # Bolty Points until those types migrate. The user-facing Point attribute
  # uses %Geo.Point{} (see #274).
  alias Bolty.Types.Point

  @moduletag :show_neo4j

  setup_all do
    BoltyHelper.start()
    :ok
  end

  test "one Place per spatial type — and one showcase Place with all five" do
    sydney_cbd_point = %Geo.Point{coordinates: {151.2093, -33.8688}, srid: 4326}

    sydney_bbox = %Box{
      sw: Point.create(:wgs_84, 151.0, -34.0),
      ne: Point.create(:wgs_84, 151.5, -33.5)
    }

    sydney_to_newcastle = %LineString{
      vertices: [
        Point.create(:wgs_84, 151.21, -33.87),
        Point.create(:wgs_84, 151.30, -33.50),
        Point.create(:wgs_84, 151.78, -32.93)
      ]
    }

    sydney_pes = %MultiPoint{
      points: [
        Point.create(:wgs_84, 151.21, -33.87),
        Point.create(:wgs_84, 151.30, -33.85),
        Point.create(:wgs_84, 151.18, -33.92)
      ]
    }

    sydney_carve_outs = %MultiBox{
      boxes: [
        %Box{sw: Point.create(:wgs_84, 151.0, -34.0), ne: Point.create(:wgs_84, 151.5, -33.5)},
        %Box{sw: Point.create(:wgs_84, 151.6, -33.4), ne: Point.create(:wgs_84, 152.0, -33.0)}
      ]
    }

    nodes = [
      {"Sydney CBD (Point)", %{location: sydney_cbd_point}},
      {"Sydney bbox (Box)", %{bounds: sydney_bbox}},
      {"Sydney to Newcastle fibre (LineString)", %{path: sydney_to_newcastle}},
      {"Sydney candidate PEs (MultiPoint)", %{pes: sydney_pes}},
      {"Sydney CSA carve-outs (MultiBox)", %{regions: sydney_carve_outs}},
      {"Spatial showcase",
       %{
         location: sydney_cbd_point,
         bounds: sydney_bbox,
         path: sydney_to_newcastle,
         pes: sydney_pes,
         regions: sydney_carve_outs
       }}
    ]

    for {name, attrs} <- nodes do
      {:ok, created} = Place |> Ash.create(Map.put(attrs, :name, name))
      {:ok, reread} = Place |> Ash.get(created.id)

      {:ok, raw} =
        Bolty.query(
          Bolt,
          "MATCH (n:SRM:Place {uuid: $uuid}) RETURN n, keys(n) AS keys",
          %{"uuid" => created.id}
        )

      [row] = raw.results

      IO.puts("\n========== #{name} ==========")
      IO.puts("Ash record (cast_stored — what consumers see):")
      IO.inspect(Map.take(reread, [:id, :name, :location, :bounds, :path, :pes, :regions]),
        label: "  reread",
        printable_limit: :infinity
      )

      IO.puts("\nRaw Neo4j properties (what's on disk, including bbox companions):")
      IO.inspect(row["n"].properties, label: "  properties", printable_limit: :infinity)
      IO.inspect(Enum.sort(row["keys"]), label: "  property keys")
    end

    IO.puts("\n========== Done ==========")
    IO.puts("All 6 Places persisted in Neo4j — no sandbox rollback.")
    IO.puts("Run `MATCH (n:SRM:Place) RETURN n` in the browser to explore.")
    IO.puts("Clean up with `MATCH (n:SRM:Place) DETACH DELETE n`.")
  end
end
