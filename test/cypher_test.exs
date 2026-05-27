# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.CypherTest do
  @moduledoc """
  End-to-end cypher predicate tests against a real Neo4j connection.
  Verifies generated Cypher fragments behave as documented when run.
  """
  use ExUnit.Case, async: true

  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Cypher
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Place
  # Bolty.Types.Point retained for direct cypher round-trip tests below
  # that bypass the Ash type system and send Bolty values straight to
  # the driver.
  alias Bolty.Types.Point

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  defp geo(lng, lat), do: %Geo.Point{coordinates: {lng, lat}, srid: 4326}

  defp sydney_polygon do
    %Geo.Polygon{
      coordinates: [
        [{151.0, -34.0}, {151.5, -34.0}, {151.5, -33.5}, {151.0, -33.5}, {151.0, -34.0}]
      ],
      srid: 4326
    }
  end

  describe "within_bbox" do
    setup do
      created = Place |> Ash.create!(%{name: "Sydney bbox", bounds: sydney_polygon()})
      {:ok, place: created}
    end

    test "matches a point inside the stored box", %{place: place} do
      inside = Point.create(:wgs_84, 151.2, -33.8)
      cypher = "MATCH (n {uuid: $uuid}) WHERE #{Cypher.expression(:n, "bounds", "within_bbox", "$test_point")} RETURN n"
      {:ok, response} = Sandbox.run(cypher, %{"uuid" => place.id, "test_point" => inside})

      assert response.results != []
    end

    test "rejects a point east of the box", %{place: place} do
      outside = Point.create(:wgs_84, 152.0, -33.8)
      cypher = "MATCH (n {uuid: $uuid}) WHERE #{Cypher.expression(:n, "bounds", "within_bbox", "$test_point")} RETURN n"
      {:ok, response} = Sandbox.run(cypher, %{"uuid" => place.id, "test_point" => outside})

      assert response.results == []
    end

    test "rejects a point south of the box", %{place: place} do
      outside = Point.create(:wgs_84, 151.2, -34.5)
      cypher = "MATCH (n {uuid: $uuid}) WHERE #{Cypher.expression(:n, "bounds", "within_bbox", "$test_point")} RETURN n"
      {:ok, response} = Sandbox.run(cypher, %{"uuid" => place.id, "test_point" => outside})

      assert response.results == []
    end

    test "matches a point on the SW corner (inclusive)", %{place: place} do
      on_corner = Point.create(:wgs_84, 151.0, -34.0)
      cypher = "MATCH (n {uuid: $uuid}) WHERE #{Cypher.expression(:n, "bounds", "within_bbox", "$test_point")} RETURN n"
      {:ok, response} = Sandbox.run(cypher, %{"uuid" => place.id, "test_point" => on_corner})

      assert response.results != []
    end
  end

  describe "st_distance" do
    setup do
      sydney = Place |> Ash.create!(%{name: "Sydney CBD", location: geo(151.2093, -33.8688)})
      {:ok, sydney: sydney}
    end

    test "matches when distance to a near point is below the threshold", %{sydney: sydney} do
      near = Point.create(:wgs_84, 151.2, -33.85)
      predicate = Cypher.expression(:n, "location.point", "st_distance", {"<", "$test_point", "$threshold"})
      cypher = "MATCH (n {uuid: $uuid}) WHERE #{predicate} RETURN n"
      {:ok, response} = Sandbox.run(cypher, %{"uuid" => sydney.id, "test_point" => near, "threshold" => 5_000.0})

      assert response.results != []
    end

    test "rejects when distance to a far point exceeds the threshold", %{sydney: sydney} do
      melbourne = Point.create(:wgs_84, 144.9631, -37.8136)
      predicate = Cypher.expression(:n, "location.point", "st_distance", {"<", "$test_point", "$threshold"})
      cypher = "MATCH (n {uuid: $uuid}) WHERE #{predicate} RETURN n"
      {:ok, response} = Sandbox.run(cypher, %{"uuid" => sydney.id, "test_point" => melbourne, "threshold" => 5_000.0})

      assert response.results == []
    end

    test "evaluates geodesically — Sydney to Melbourne is ~713 km", %{sydney: sydney} do
      melbourne = Point.create(:wgs_84, 144.9631, -37.8136)
      predicate = Cypher.expression(:n, "location.point", "st_distance", {">", "$test_point", "$threshold"})
      cypher = "MATCH (n {uuid: $uuid}) WHERE #{predicate} RETURN n"
      # Threshold just under expected distance — should match.
      {:ok, hit} = Sandbox.run(cypher, %{"uuid" => sydney.id, "test_point" => melbourne, "threshold" => 700_000.0})
      assert hit.results != []

      # Threshold just over expected distance — should not match.
      {:ok, miss} = Sandbox.run(cypher, %{"uuid" => sydney.id, "test_point" => melbourne, "threshold" => 800_000.0})
      assert miss.results == []
    end

    test ">= operator works", %{sydney: sydney} do
      melbourne = Point.create(:wgs_84, 144.9631, -37.8136)
      predicate = Cypher.expression(:n, "location.point", "st_distance", {">=", "$test_point", "$threshold"})
      cypher = "MATCH (n {uuid: $uuid}) WHERE #{predicate} RETURN n"
      {:ok, response} = Sandbox.run(cypher, %{"uuid" => sydney.id, "test_point" => melbourne, "threshold" => 700_000.0})

      assert response.results != []
    end
  end

  describe "in-memory combination building blocks — branch_node_read_ids and node_read_by_ids" do
    setup do
      sydney = Place |> Ash.create!(%{name: "Sydney CBD", location: geo(151.2093, -33.8688)})
      melbourne = Place |> Ash.create!(%{name: "Melbourne CBD", location: geo(144.9631, -37.8136)})
      perth = Place |> Ash.create!(%{name: "Perth CBD", location: geo(115.8617, -31.9514)})
      {:ok, sydney: sydney, melbourne: melbourne, perth: perth}
    end

    test "branch_node_read_ids returns id(s) AS sid for matching nodes", %{sydney: sydney} do
      query = AshNeo4j.Cypher.Query.branch_node_read_ids([:SRM, :Place], [{"name", :==, "Sydney CBD", false}], param_prefix: "b0_")
      {cypher, params} = AshNeo4j.Cypher.render(query)
      {:ok, response} = Sandbox.run(cypher, params)

      sids = Enum.map(response.results, &Map.get(&1, "sid"))
      assert length(sids) == 1
      assert is_integer(hd(sids))

      # Verify the sid is the id of the sydney node via a follow-up read.
      sid = hd(sids)
      {:ok, follow} = Sandbox.run("MATCH (n) WHERE id(n) = $sid RETURN n.uuid AS uuid", %{"sid" => sid})
      assert hd(follow.results)["uuid"] == sydney.id
    end

    test "node_read_by_ids fetches multiple nodes by id with OPTIONAL MATCH enrichment", %{sydney: sydney, melbourne: melbourne} do
      # First collect the ids for sydney and melbourne via separate branch reads.
      b0 = AshNeo4j.Cypher.Query.branch_node_read_ids([:SRM, :Place], [{"name", :==, "Sydney CBD", false}], param_prefix: "b0_")
      b1 = AshNeo4j.Cypher.Query.branch_node_read_ids([:SRM, :Place], [{"name", :==, "Melbourne CBD", false}], param_prefix: "b1_")

      {c0, p0} = AshNeo4j.Cypher.render(b0)
      {c1, p1} = AshNeo4j.Cypher.render(b1)
      {:ok, r0} = Sandbox.run(c0, p0)
      {:ok, r1} = Sandbox.run(c1, p1)
      ids = Enum.map(r0.results ++ r1.results, &Map.get(&1, "sid"))

      # Now fetch via node_read_by_ids.
      final = AshNeo4j.Cypher.Query.node_read_by_ids([:SRM, :Place], ids)
      {cypher, params} = AshNeo4j.Cypher.render(final)
      {:ok, response} = Sandbox.run(cypher, params)

      uuids = Enum.map(response.results, &Map.get(&1["s"].properties, "uuid"))
      assert sydney.id in uuids
      assert melbourne.id in uuids
      assert length(response.results) == 2
    end

    test "node_read_by_ids with empty id list returns no results", %{sydney: _sydney} do
      final = AshNeo4j.Cypher.Query.node_read_by_ids([:SRM, :Place], [])
      {cypher, params} = AshNeo4j.Cypher.render(final)
      {:ok, response} = Sandbox.run(cypher, params)

      assert response.results == []
    end
  end

  describe "combination_block — CALL { … UNION/UNION ALL … } end-to-end" do
    setup do
      sydney = Place |> Ash.create!(%{name: "Sydney CBD", location: geo(151.2093, -33.8688)})
      melbourne = Place |> Ash.create!(%{name: "Melbourne CBD", location: geo(144.9631, -37.8136)})
      perth = Place |> Ash.create!(%{name: "Perth CBD", location: geo(115.8617, -31.9514)})
      {:ok, sydney: sydney, melbourne: melbourne, perth: perth}
    end

    test "UNION ALL of two non-overlapping branches returns both", %{sydney: sydney, melbourne: melbourne} do
      b0 = AshNeo4j.Cypher.Query.branch_node_read([:SRM, :Place], [{"name", :==, "Sydney CBD", false}], param_prefix: "b0_")
      b1 = AshNeo4j.Cypher.Query.branch_node_read([:SRM, :Place], [{"name", :==, "Melbourne CBD", false}], param_prefix: "b1_")
      query = AshNeo4j.Cypher.Query.combination_block([b0, b1])
      {cypher, params} = AshNeo4j.Cypher.render(query)
      {:ok, response} = Sandbox.run(cypher, params)

      uuids = Enum.map(response.results, &Map.get(&1["s"].properties, "uuid"))
      assert sydney.id in uuids
      assert melbourne.id in uuids
    end

    test "UNION ALL of overlapping branches keeps duplicates", %{sydney: sydney} do
      b0 = AshNeo4j.Cypher.Query.branch_node_read([:SRM, :Place], [{"name", :==, "Sydney CBD", false}], param_prefix: "b0_")
      b1 = AshNeo4j.Cypher.Query.branch_node_read([:SRM, :Place], [{"name", :contains, "Sydney", false}], param_prefix: "b1_")
      query = AshNeo4j.Cypher.Query.combination_block([b0, b1], union_type: :union_all)
      {cypher, params} = AshNeo4j.Cypher.render(query)
      {:ok, response} = Sandbox.run(cypher, params)

      uuids = Enum.map(response.results, &Map.get(&1["s"].properties, "uuid"))
      assert Enum.count(uuids, &(&1 == sydney.id)) == 2
    end

    test "UNION (default-deduplicated) of overlapping branches keeps unique rows", %{sydney: sydney} do
      b0 = AshNeo4j.Cypher.Query.branch_node_read([:SRM, :Place], [{"name", :==, "Sydney CBD", false}], param_prefix: "b0_")
      b1 = AshNeo4j.Cypher.Query.branch_node_read([:SRM, :Place], [{"name", :contains, "Sydney", false}], param_prefix: "b1_")
      query = AshNeo4j.Cypher.Query.combination_block([b0, b1], union_type: :union)
      {cypher, params} = AshNeo4j.Cypher.render(query)
      {:ok, response} = Sandbox.run(cypher, params)

      uuids = Enum.map(response.results, &Map.get(&1["s"].properties, "uuid"))
      assert Enum.count(uuids, &(&1 == sydney.id)) == 1
    end
  end

  describe "%Geo.Point{} ↔ native Neo4j POINT boundary — for #274 rearchitecture" do
    test "Geo.Point coordinates round-trip through a native Neo4j POINT property" do
      # Bolty packs %Bolty.Types.Point{} natively. The type-module boundary
      # for #274's AshNeo4j.Type.Point will convert %Geo.Point{} → Bolty
      # on dump_to_native and reverse on cast_stored. Verify both legs.
      sydney_geo = %Geo.Point{coordinates: {151.2093, -33.8688}, srid: 4326}

      sydney_bolty = Point.create(:wgs_84, elem(sydney_geo.coordinates, 0), elem(sydney_geo.coordinates, 1))
      {:ok, _} = Sandbox.run("CREATE (n:RoundTrip {tag: $tag, p: $p}) RETURN n", %{"tag" => "geo_pt", "p" => sydney_bolty})

      {:ok, response} = Sandbox.run("MATCH (n:RoundTrip {tag: $tag}) RETURN n.p AS p", %{"tag" => "geo_pt"})
      [%{"p" => %Point{} = loaded}] = response.results

      back_to_geo = %Geo.Point{coordinates: {loaded.x, loaded.y}, srid: 4326}
      assert back_to_geo == sydney_geo
    end
  end

  describe "LIST<POINT> round-trip — N-length vertex arrays for multi-vertex types" do
    test "round-trips a 7-point list intact (LineString shape)" do
      pts = for i <- 0..6, do: Point.create(:wgs_84, 151.0 + i * 0.1, -33.5 - i * 0.1)
      {:ok, _} = Sandbox.run("CREATE (n:RoundTrip {tag: $tag, path: $path}) RETURN n", %{"tag" => "lp", "path" => pts})
      {:ok, response} = Sandbox.run("MATCH (n:RoundTrip {tag: $tag}) RETURN n.path AS path", %{"tag" => "lp"})

      [%{"path" => loaded}] = response.results
      assert length(loaded) == 7
      assert Enum.all?(loaded, &match?(%Point{srid: 4326}, &1))
      assert Enum.map(loaded, & &1.x) == Enum.map(pts, & &1.x)
      assert Enum.map(loaded, & &1.y) == Enum.map(pts, & &1.y)
    end

    test "round-trips a 12-point list intact (MultiBox shape — 3 boxes × 4 corners)" do
      pts = for i <- 0..11, do: Point.create(:wgs_84, 150.0 + i * 0.05, -34.0 + i * 0.05)
      {:ok, _} = Sandbox.run("CREATE (n:RoundTrip {tag: $tag, boxes: $boxes}) RETURN n", %{"tag" => "mb", "boxes" => pts})
      {:ok, response} = Sandbox.run("MATCH (n:RoundTrip {tag: $tag}) RETURN n.boxes AS boxes", %{"tag" => "mb"})

      [%{"boxes" => loaded}] = response.results
      assert length(loaded) == 12
      assert Enum.map(loaded, & &1.x) == Enum.map(pts, & &1.x)
    end
  end

  describe "dwithin" do
    setup do
      sydney = Place |> Ash.create!(%{name: "Sydney CBD", location: geo(151.2093, -33.8688)})
      {:ok, sydney: sydney}
    end

    test "matches when distance is within the threshold", %{sydney: sydney} do
      near = Point.create(:wgs_84, 151.2, -33.85)
      predicate = Cypher.expression(:n, "location.point", "dwithin", {"$test_point", "$threshold"})
      cypher = "MATCH (n {uuid: $uuid}) WHERE #{predicate} RETURN n"
      {:ok, response} = Sandbox.run(cypher, %{"uuid" => sydney.id, "test_point" => near, "threshold" => 5_000.0})

      assert response.results != []
    end

    test "rejects when distance exceeds the threshold", %{sydney: sydney} do
      melbourne = Point.create(:wgs_84, 144.9631, -37.8136)
      predicate = Cypher.expression(:n, "location.point", "dwithin", {"$test_point", "$threshold"})
      cypher = "MATCH (n {uuid: $uuid}) WHERE #{predicate} RETURN n"
      {:ok, response} = Sandbox.run(cypher, %{"uuid" => sydney.id, "test_point" => melbourne, "threshold" => 5_000.0})

      assert response.results == []
    end

    test "boundary is inclusive — Sydney to Melbourne at ~713 km", %{sydney: sydney} do
      melbourne = Point.create(:wgs_84, 144.9631, -37.8136)
      predicate = Cypher.expression(:n, "location.point", "dwithin", {"$test_point", "$threshold"})
      cypher = "MATCH (n {uuid: $uuid}) WHERE #{predicate} RETURN n"

      # Threshold larger than actual distance — should match.
      {:ok, hit} = Sandbox.run(cypher, %{"uuid" => sydney.id, "test_point" => melbourne, "threshold" => 800_000.0})
      assert hit.results != []

      # Threshold smaller than actual distance — should not match.
      {:ok, miss} = Sandbox.run(cypher, %{"uuid" => sydney.id, "test_point" => melbourne, "threshold" => 700_000.0})
      assert miss.results == []
    end
  end
end
