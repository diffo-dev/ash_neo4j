<!--
SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Geospatial benchmarks (#306)

Measures AshNeo4j's spatial pushdown against a Neo4j POINT index, with and
without the index, for point-in-polygon containment and 2D/3D distance.

```sh
MIX_ENV=test mix run bench/spatial_containment.exs              # N = 1000
BENCH_N=10000 MIX_ENV=test mix run bench/spatial_containment.exs
```

Benchmarks **commit** data (they don't use the rollback sandbox); fixtures are
tagged `bench_csa_*` and cleaned up before and after each run.

## Model

Each `Place` is an NBN-style CSA:

* `bounds` — a square "donut" polygon: an exterior ring with a central NSA
  hole, so containment is genuinely hole-aware (a point in the hole is *not*
  contained).
* `location` — a 2D `%Geo.Point{}` at the CSA centre.
* `tower` — a 3D `%Geo.PointZ{}` (WGS-84-3D, srid 4979).

`N` CSAs sit on a non-overlapping grid. Three queries run against the same
seeded set, each unindexed then indexed:

| query | pushdown |
| --- | --- |
| `st_contains(bounds, ^p)` | `point.withinBBox` bbox prefilter + topo refine |
| `st_dwithin(location, ^p, r)` | `point.distance` on the 2D `.point` companion |
| `st_dwithin(tower, ^p3, r)` | `point.distance` on the 3D `.point` companion |

## Results

Neo4j 5.26 (Bolt @ 7687), bolty 0.1.0. `time: 3, warmup: 1`. Median latency.

**N = 1 000**

| query | unindexed | indexed | speedup |
| --- | --- | --- | --- |
| `st_contains` | 2.72 ms | 1.97 ms | ~1.4× |
| `st_dwithin` 2D | 3.61 ms | 0.92 ms | ~3.9× |
| `st_dwithin` 3D | 3.35 ms | 0.93 ms | ~3.6× |

**N = 10 000**

| query | unindexed | indexed | speedup |
| --- | --- | --- | --- |
| `st_contains` | 5.47 ms | 4.32 ms | ~1.3× |
| `st_dwithin` 2D | 5.65 ms | 0.78 ms | ~7.2× |
| `st_dwithin` 3D | 5.14 ms | 0.88 ms | ~5.8× |

Indexed distance is roughly **flat as N grows** (constant-time index seek),
while unindexed scales with N — so the distance speedup widens with scale.

## Findings (#311)

These benchmarks surfaced two index-effectiveness bugs, both fixed in #311
before these numbers were taken:

1. **3D `point_z` had no usable index.** `AshNeo4j.Spatial` built the index on
   `.bbSW`/`.bbNE` for a `:point_z` attribute — companions a `%Geo.PointZ{}`
   never writes — so 3D `st_dwithin` could not use an index at all. The 3D row
   above only exists because `point_z` now indexes its `.point` companion.

2. **Containment couldn't use the index.** The original
   `point.withinBBox($p, n.bbSW, n.bbNE)` form puts the indexed properties in
   the *box* position, so Neo4j plans a `NodeByLabelScan`. The reformulation to
   range scans on the indexed corners (`point.withinBBox(n.bbSW, worldSW, $p)
   AND point.withinBBox(n.bbNE, $p, worldNE)`) plans a `NodeIndexSeekByRange` on
   `bounds.bbSW` with `bbNE` as a residual filter — confirmed by `EXPLAIN`.

**Why containment's speedup is modest** (~1.3–1.4× vs. distance's 6–7×): a
point-containment seek ranges on a *single* indexed corner against an
open-ended world box, so `bbSW ≤ p` selects roughly a quadrant of candidates
before the `bbNE` filter narrows to the hit. The index removes the guaranteed
full scan, but the quadrant candidate set still grows with N. Distance queries,
by contrast, seek a truly *bounded* range, so they stay near-constant.

The open quadrant is **mandatory for correctness**: a box that contains `p` can
have its SW corner arbitrarily far away (a huge polygon), so the seek can't be
tightened without bounding the polygon *size*. A "max-extent" bound (seek
`bbSW ∈ [p − E, p]`) is **infeasible for the real workload**: NBN CSAs are
uniform in homes-passed, not area — metro CSAs are tiny, remote ones enormous
(the Northern Territory is a single CSA) — so `E` is pinned by the largest box
and the seek collapses back to ~full scan. The benchmark seeds *uniform*-size
CSAs and so **under-represents** this skew; real-world containment is harder,
not easier, than these numbers suggest.

**Recommendation.** Treat **distance as the indexed path** (`st_dwithin`,
clean 6–7×). For **containment**, the POINT-index reformulation (#311) is the
correct query shape and strictly better than the old full scan, but the index
is optional — the realistic indexed path to ≥3× is an adaptive tile/cell index
(skew-immune), and beyond that a sub-graph / B-rep topological model. Both are
out of scope here and tracked as a follow-up epic.

Auxiliary probe (`bench/bbox_index_probe.exs`) `EXPLAIN`s the old vs. new
containment forms directly, showing `NodeByLabelScan` → `NodeIndexSeekByRange`.
