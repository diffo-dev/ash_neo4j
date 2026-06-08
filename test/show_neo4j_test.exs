# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.ShowNeo4jTest do
  @moduledoc """
  Tests tagged `:show_neo4j` build spatial Place nodes in the **real**
  Neo4j database (no sandbox, no rollback) so the nodes can be
  inspected via the Neo4j browser afterwards.

  Each test prints the Ash-side record and a raw Cypher dump of the
  on-disk node properties. Under #274's rearchitecture, every non-Point
  geometry stores as **RFC 7946 GeoJSON** at `<attr>.json` plus scalar
  `<attr>.bbSW` / `<attr>.bbNE` companions for indexable bbox prefilter.
  Point splits across native `<attr>.point` (the indexable form) plus
  `<attr>.json` (self-describing canonical).

  Run with:

      mix test --only show_neo4j

  Excluded from default test runs.

  Useful Cypher snippets to paste into Neo4j browser after running:

      // All Places created by this test
      MATCH (n:SRM:Place) RETURN n

      // The showcase node with every spatial type populated
      MATCH (n:SRM:Place {name: 'Spatial showcase'}) RETURN n

      // Inspect raw property keys including the dotted companions
      MATCH (n:SRM:Place {name: 'Spatial showcase'}) RETURN keys(n) AS props

      // Bounding-box prefilter via the indexed scalar companions —
      // works uniformly for path, bounds, pes, regions. Probing the indexed
      // corners against world-extent boxes lets the POINT index serve the
      // ranges (#311) — equivalent to "test point ∈ [bbSW, bbNE]".
      MATCH (n:SRM:Place)
      WHERE n.`path.bbSW` IS NOT NULL
        AND point.withinBBox(
          n.`path.bbSW`,
          point({longitude: -180, latitude: -90}),
          point({longitude: 151.25, latitude: -33.7})
        )
        AND point.withinBBox(
          n.`path.bbNE`,
          point({longitude: 151.25, latitude: -33.7}),
          point({longitude: 180, latitude: 90})
        )
      RETURN n.name, n.`path.json`

      // Server-side `point.distance` pushdown via the native Point
      // companion (Point is the one geometry with a native Neo4j form)
      MATCH (n:SRM:Place)
      WHERE n.`location.point` IS NOT NULL
        AND point.distance(
          n.`location.point`,
          point({longitude: 151.21, latitude: -33.87})
        ) < 5000
      RETURN n.name, n.`location.json`

  Clean up afterwards with:

      MATCH (n:SRM:Place) DETACH DELETE n
  """
  use ExUnit.Case, async: false

  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Test.Resource.Place

  @moduletag :show_neo4j

  setup_all do
    BoltyHelper.start()
    :ok
  end

  test "one Place per spatial type — and one showcase Place with all five" do
    sydney_cbd_point = %Geo.Point{coordinates: {151.2093, -33.8688}, srid: 4326}

    sydney_bbox = %Geo.Polygon{
      coordinates: [
        [{151.0, -34.0}, {151.5, -34.0}, {151.5, -33.5}, {151.0, -33.5}, {151.0, -34.0}]
      ],
      srid: 4326
    }

    sydney_to_newcastle = %Geo.LineString{
      coordinates: [{151.21, -33.87}, {151.30, -33.50}, {151.78, -32.93}],
      srid: 4326
    }

    sydney_pes = %Geo.MultiPoint{
      coordinates: [{151.21, -33.87}, {151.30, -33.85}, {151.18, -33.92}],
      srid: 4326
    }

    sydney_carve_outs = %Geo.MultiPolygon{
      coordinates: [
        [[{151.0, -34.0}, {151.5, -34.0}, {151.5, -33.5}, {151.0, -33.5}, {151.0, -34.0}]],
        [[{151.6, -33.4}, {152.0, -33.4}, {152.0, -33.0}, {151.6, -33.0}, {151.6, -33.4}]]
      ],
      srid: 4326
    }

    nodes = [
      {"Sydney CBD (Point)", %{location: sydney_cbd_point}},
      {"Sydney bbox (Polygon)", %{bounds: sydney_bbox}},
      {"Sydney to Newcastle fibre (LineString)", %{path: sydney_to_newcastle}},
      {"Sydney candidate PEs (MultiPoint)", %{pes: sydney_pes}},
      {"Sydney CSA carve-outs (MultiPolygon)", %{regions: sydney_carve_outs}},
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
          "MATCH (n:SRM:Place {uuid: $uuid}) RETURN n, labels(n) AS labels, keys(n) AS keys",
          %{"uuid" => created.id}
        )

      [row] = raw.results

      IO.puts("\n========== #{name} ==========")
      IO.puts("Ash record (cast_stored — what consumers see):")
      IO.inspect(Map.take(reread, [:id, :name, :location, :bounds, :path, :pes, :regions]),
        label: "  reread",
        printable_limit: :infinity
      )

      IO.puts("\nRaw Neo4j node (what's on disk):")
      IO.inspect(Enum.sort(row["labels"]), label: "  labels")
      IO.inspect(Enum.sort(row["keys"]), label: "  property keys")
      IO.inspect(row["n"].properties, label: "  properties", printable_limit: :infinity)
    end

    IO.puts("\n========== Done ==========")
    IO.puts("All 6 Places persisted in Neo4j — no sandbox rollback.")
    IO.puts("Run `MATCH (n:SRM:Place) RETURN n` in the browser to explore.")
    IO.puts("Clean up with `MATCH (n:SRM:Place) DETACH DELETE n`.")
  end
end
