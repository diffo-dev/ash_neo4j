# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

# #306 investigation: why doesn't the POINT index accelerate the st_contains
# `withinBBox` prefilter, and would a reformulation fix it?
#
#   BENCH_N=10000 MIX_ENV=test mix run bench/bbox_index_probe.exs
#
# Compares two equivalent bbox-containment prefilters over N indexed CSA bboxes:
#   A (current): point.withinBBox($p, n.bbSW, n.bbNE)   — literal point in node box
#   B (proposed): point.withinBBox(n.bbSW, worldSW, $p)
#                   AND point.withinBBox(n.bbNE, $p, worldNE)  — indexed corners vs literal boxes
# Same answer; B is the index-servable shape.

defmodule Probe do
  alias AshNeo4j.Cypher
  alias AshNeo4j.Test.Resource.Place

  @s 0.01
  @spacing @s * 3
  @origin {151.0, -33.0}

  def csa(cx, cy), do: %Geo.Polygon{coordinates: [ring(cx, cy, @s), ring(cx, cy, @s / 4)], srid: 4326}
  defp ring(cx, cy, r), do: [{cx - r, cy - r}, {cx + r, cy - r}, {cx + r, cy + r}, {cx - r, cy + r}, {cx - r, cy - r}]

  def centres(n) do
    side = :math.sqrt(n) |> Float.ceil() |> trunc()
    {ox, oy} = @origin
    for i <- 0..(n - 1), do: {ox + rem(i, side) * @spacing, oy + div(i, side) * @spacing}
  end

  def cleanup, do: Cypher.run("MATCH (n:Place) WHERE n.name STARTS WITH 'bench_csa_' DETACH DELETE n")

  def seed(centres) do
    centres
    |> Enum.with_index()
    |> Enum.each(fn {{cx, cy}, i} -> Place |> Ash.create!(%{name: "bench_csa_#{i}", bounds: csa(cx, cy)}) end)
  end

  def index do
    AshNeo4j.Spatial.create_index(Place, :bounds)
    wait()
  end

  defp wait(t \\ 50) do
    {:ok, r} = Cypher.run("SHOW INDEXES YIELD name, state WHERE name STARTS WITH 'place_bounds' RETURN state")
    s = Enum.map(r.results, & &1["state"])
    if (s != [] and Enum.all?(s, &(&1 == "ONLINE"))) or t <= 0, do: :ok, else: Process.sleep(100) && wait(t - 1)
  end

  def time(cypher, params, runs \\ 200) do
    Cypher.run(cypher, params)  # warm
    {us, last} = :timer.tc(fn -> Enum.reduce(1..runs, nil, fn _, _ -> Cypher.run(cypher, params) end) end)
    {:ok, %{results: [%{"c" => count}]}} = last
    {Float.round(us / runs / 1000, 3), count}
  end

  def explain(cypher, params) do
    case Cypher.run("EXPLAIN " <> cypher, params) do
      {:ok, resp} -> Map.get(resp, :plan) || Map.get(resp, :notifications) || :no_plan_in_response
      other -> other
    end
  end
end

AshNeo4j.BoltyHelper.start()
n = System.get_env("BENCH_N", "10000") |> String.to_integer()
IO.puts("\n#306 bbox-index probe — N = #{n}\n")

Probe.cleanup()
centres = Probe.centres(n)
IO.puts("seeding #{n} …")
{su, _} = :timer.tc(fn -> Probe.seed(centres) end)
IO.puts("seeded in #{Float.round(su / 1_000_000, 1)} s")
Probe.index()

{tx, ty} = Enum.at(centres, div(n, 2))
p = Bolty.Types.Point.create(:wgs_84, tx + 0.005, ty)  # served point of the middle CSA
params = %{"p" => p}

form_a = ~s|MATCH (s:Place) WHERE point.withinBBox($p, s.`bounds.bbSW`, s.`bounds.bbNE`) RETURN count(s) AS c|

form_b =
  ~s|MATCH (s:Place) WHERE point.withinBBox(s.`bounds.bbSW`, point({longitude:-180,latitude:-90}), $p) | <>
    ~s|AND point.withinBBox(s.`bounds.bbNE`, $p, point({longitude:180,latitude:90})) RETURN count(s) AS c|

{ta, ca} = Probe.time(form_a, params)
{tb, cb} = Probe.time(form_b, params)

IO.puts("""

results (both should find the same CSAs whose bbox contains the point):
  A current      withinBBox($p, n.bbSW, n.bbNE)     count=#{ca}   #{ta} ms/query
  B reformulated withinBBox(n.bbSW,…,$p) AND …      count=#{cb}   #{tb} ms/query
  equivalent? #{ca == cb}   speedup: #{if tb > 0, do: Float.round(ta / tb, 1), else: "∞"}x
""")

IO.puts("--- EXPLAIN A ---")
IO.inspect(Probe.explain(form_a, params), limit: :infinity)
IO.puts("--- EXPLAIN B ---")
IO.inspect(Probe.explain(form_b, params), limit: :infinity)

Probe.cleanup()
IO.puts("\ncleaned up.\n")
