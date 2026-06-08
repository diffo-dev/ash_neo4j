# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

# Geospatial benchmark (#306): point-in-CSA containment + distance queries over
# NBN-style CSAs (a polygon with an NSA hole), 2D and 3D, indexed vs unindexed.
#
#   MIX_ENV=test mix run bench/spatial_containment.exs
#   BENCH_N=10000 MIX_ENV=test mix run bench/spatial_containment.exs
#
# Each Place is a CSA: a `bounds` square donut (exterior ring + central NSA hole),
# a `location` Point at the CSA centre (2D), and a `tower` PointZ (3D). N CSAs sit
# on a non-overlapping grid. We measure three queries against the same seeded set,
# each with and without the relevant POINT index:
#
#   * st_contains(bounds, ^p)        — `point.withinBBox` bbox prefilter + topo
#   * st_dwithin(location, ^p, r)    — `point.distance` on the 2D point companion
#   * st_dwithin(tower, ^p3, r)      — `point.distance` on the 3D point companion
#
# Benchmarks commit data (not the rollback sandbox); fixtures are tagged
# `bench_csa_*` and cleaned up before and after.

defmodule Bench.Spatial do
  require Ash.Query
  alias AshNeo4j.Cypher
  alias AshNeo4j.Test.Resource.Place

  @s 0.01           # CSA half-width in degrees (~1.1 km)
  @hole @s / 4      # central NSA hole half-width
  @spacing @s * 3   # grid spacing — > 2*@s so CSAs never overlap
  @origin {151.0, -33.0}
  @radius 1_000.0   # dwithin radius (m) — well under the ~2.8 km grid spacing

  def csa(cx, cy), do: %Geo.Polygon{coordinates: [ring(cx, cy, @s), ring(cx, cy, @hole)], srid: 4326}
  defp ring(cx, cy, r), do: [{cx - r, cy - r}, {cx + r, cy - r}, {cx + r, cy + r}, {cx - r, cy + r}, {cx - r, cy - r}]

  def point(x, y), do: %Geo.Point{coordinates: {x, y}, srid: 4326}
  def point3(x, y, z), do: %Geo.PointZ{coordinates: {x, y, z}, srid: 4979}

  def served(cx, cy), do: point(cx + @s / 2, cy)
  def excluded(cx, cy), do: point(cx, cy)
  def outside(cx, cy), do: point(cx + 1.5 * @s, cy)

  def centres(n) do
    side = :math.sqrt(n) |> Float.ceil() |> trunc()
    {ox, oy} = @origin
    for i <- 0..(n - 1), do: {ox + rem(i, side) * @spacing, oy + div(i, side) * @spacing}
  end

  def cleanup, do: Cypher.run("MATCH (n:Place) WHERE n.name STARTS WITH 'bench_csa_' DETACH DELETE n")

  def seed(centres) do
    centres
    |> Enum.with_index()
    |> Enum.each(fn {{cx, cy}, i} ->
      Place
      |> Ash.create!(%{
        name: "bench_csa_#{i}",
        bounds: csa(cx, cy),
        location: point(cx, cy),
        tower: point3(cx, cy, 50.0)
      })
    end)
  end

  def contains(p), do: Place |> Ash.Query.filter(st_contains(bounds, ^p)) |> Ash.read!()
  def dwithin_2d(p), do: Place |> Ash.Query.filter(st_dwithin(location, ^p, @radius)) |> Ash.read!()
  def dwithin_3d(p), do: Place |> Ash.Query.filter(st_dwithin(tower, ^p, @radius)) |> Ash.read!()

  def drop_index(attr), do: AshNeo4j.Spatial.drop_index(Place, attr)

  def create_index(attr) do
    AshNeo4j.Spatial.create_index(Place, attr)
    wait_online(attr)
  end

  defp wait_online(attr, tries \\ 50) do
    {:ok, resp} = Cypher.run("SHOW INDEXES YIELD name, state WHERE name STARTS WITH 'place_#{attr}' RETURN state")
    states = Enum.map(resp.results, & &1["state"])

    cond do
      states != [] and Enum.all?(states, &(&1 == "ONLINE")) -> :ok
      tries <= 0 -> :ok
      true -> Process.sleep(100) && wait_online(attr, tries - 1)
    end
  end

  # Run a query unindexed then indexed, for the given index attribute.
  def scenario(label, query_fn, index_attr) do
    IO.puts("\n##### #{label} #####")
    drop_index(index_attr)
    Benchee.run(%{"#{label} (unindexed)" => query_fn}, time: 3, warmup: 1, print: [configuration: false])
    create_index(index_attr)
    Benchee.run(%{"#{label} (indexed)" => query_fn}, time: 3, warmup: 1, print: [configuration: false])
    drop_index(index_attr)
  end
end

alias Bench.Spatial, as: B

AshNeo4j.BoltyHelper.start()

n = System.get_env("BENCH_N", "1000") |> String.to_integer()
IO.puts("\n#306 spatial benchmarks — N = #{n} CSAs (square donut + NSA hole; 2D & 3D companions)\n")

B.cleanup()
centres = B.centres(n)
IO.puts("seeding #{n} CSAs (committed) …")
{seed_us, _} = :timer.tc(fn -> B.seed(centres) end)
IO.puts("seeded in #{Float.round(seed_us / 1_000_000, 1)} s")

{tx, ty} = Enum.at(centres, div(n, 2))
served = B.served(tx, ty)
target = "bench_csa_#{div(n, 2)}"

# --- correctness (hole-aware containment) ---------------------------------
B.create_index(:bounds)
served_hits = B.contains(served) |> Enum.map(& &1.name)
excluded_hits = B.contains(B.excluded(tx, ty)) |> Enum.map(& &1.name)
outside_hits = B.contains(B.outside(tx, ty)) |> Enum.map(& &1.name)
B.drop_index(:bounds)

IO.puts("""

correctness:
  served   → contains target?  #{target in served_hits} (hits: #{length(served_hits)})
  excluded → excludes target?  #{target not in excluded_hits} (in a hole; hits: #{length(excluded_hits)})
  outside  → no hits?          #{outside_hits == []}
""")

# --- the three scenarios, indexed vs unindexed ----------------------------
B.scenario("st_contains (point-in-CSA, withinBBox prefilter)", fn -> B.contains(served) end, :bounds)
B.scenario("st_dwithin 2D (point.distance)", fn -> B.dwithin_2d(B.point(tx, ty)) end, :location)
B.scenario("st_dwithin 3D (point.distance)", fn -> B.dwithin_3d(B.point3(tx, ty, 50.0)) end, :tower)

B.cleanup()
IO.puts("\ncleaned up.\n")
