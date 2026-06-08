<!--
SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Spatial types and expressions

AshNeo4j stores geometries using [`ash_geo`](https://hex.pm/packages/ash_geo) types at the Ash boundary and `st_*` expression functions matching ash_geo / PostGIS signatures. Predicates push down to native Cypher (`point.distance`, `point.withinBBox`) where possible, falling back to in-memory evaluation otherwise. WGS-84 2D throughout, plus **WGS-84-3D points** (#270 — see **3D points** below).

> **Changed in 0.8.0.** The whole spatial surface was rearchitected (#274). The previous `AshNeo4j.Type.Point` / `AshNeo4j.Type.Box` modules are gone. Attributes now use `AshGeo.GeoJson` (or `AshGeo.GeoAny`) and carry `%Geo.*{}` structs. See the breaking-change notes in `CHANGELOG.md` and the **Migrating from 0.7.0** section below.

## Declaring spatial attributes

Use `AshGeo.GeoJson` with a `geo_types` constraint naming the geometry kind, plus `force_srid: 4326` (WGS-84):

```elixir
attributes do
  attribute :location, AshGeo.GeoJson, constraints: [geo_types: [:point], force_srid: 4326]
  attribute :bounds,   AshGeo.GeoJson, constraints: [geo_types: [:polygon], force_srid: 4326]
  attribute :path,     AshGeo.GeoJson, constraints: [geo_types: [:line_string], force_srid: 4326]
  attribute :pes,      AshGeo.GeoJson, constraints: [geo_types: [:multi_point], force_srid: 4326]
  attribute :regions,  AshGeo.GeoJson, constraints: [geo_types: [:multi_polygon], force_srid: 4326]
end
```

> Use the **list** form `geo_types: [:point]`, not the bare atom `geo_types: :point` — the bare atom currently crashes ash_geo's constraint error formatter on validation failure ([ash_geo#13](https://github.com/bcksl/ash_geo/pull/13) fixes it upstream).

Values are [`Geo`](https://hex.pm/packages/geo) structs — `Bolty.Types.Point` no longer appears at the Ash boundary:

```elixir
Place |> Ash.create!(%{
  name: "Sydney CBD",
  location: %Geo.Point{coordinates: {151.2093, -33.8688}, srid: 4326}
})

Place |> Ash.create!(%{
  name: "Sydney bbox",
  bounds: %Geo.Polygon{
    coordinates: [[{151.0, -34.0}, {151.5, -34.0}, {151.5, -33.5}, {151.0, -33.5}, {151.0, -34.0}]],
    srid: 4326
  }
})
```

`AshGeo.GeoJson` also accepts GeoJSON-shaped maps (`%{"type" => "Point", "coordinates" => [...]}`) and `AshGeo.GeoAny` additionally accepts WKT/WKB strings — handy for ingesting external data. Use `AshGeo.GeoAny` when an attribute can hold any geometry kind.

## On-disk shape

The data layer translates each geometry to a canonical RFC 7946 GeoJSON `STRING` plus **indexable companion properties**. You never declare the companions — the data layer writes them automatically.

**Point** (the one geometry with a native Neo4j counterpart) splits into:

```
location.point  = native Neo4j POINT     (indexable; point.distance / point.withinBBox)
location.json   = "{...RFC 7946 GeoJSON...}"  (canonical, self-describing)
```

**Every other geometry** (Polygon, LineString, MultiPoint, MultiLineString, MultiPolygon) stores:

```
bounds.json   = "{...RFC 7946 GeoJSON...}"  (canonical)
bounds.bbSW   = native Neo4j POINT          (bounding-box SW corner — indexable)
bounds.bbNE   = native Neo4j POINT          (bounding-box NE corner — indexable)
```

Nothing is stored at the bare attribute key for geometries — every property's role is in its suffix. The dotted companion names are backticked in any Cypher you write directly (`` n.`bounds.bbSW` ``, `` n.`location.point` ``).

The on-disk GeoJSON is strict RFC 7946 (no `crs` member, `bbox` member included), so any GIS tool can ingest a `RETURN n.`bounds.json`` result directly.

## Recursive geo-promotion — nested geometries are indexable too

A geometry **nested inside another attribute** — a `Ash.TypedStruct` field, an embedded resource, a map — gets its indexable companion promoted to a node-level property at the dotted path, even though the parent value stores as a single JSON blob.

```elixir
# A TypedStruct with a nested geo field
defmodule MyApp.Characteristic do
  use Ash.TypedStruct

  typed_struct do
    field :name, :string
    field :location, AshGeo.GeoJson, constraints: [geo_types: [:point], force_srid: 4326]
  end
end

# On a resource
attribute :characteristic, MyApp.Characteristic, public?: true
```

A created node carries:

```
characteristic              = "{...JSON with the nested GeoJSON inline...}"
characteristic.location.point = native Neo4j POINT   (promoted, indexable)
```

So a nested location is **indexable from any depth**:

```cypher
MATCH (n)
WHERE point.distance(n.`characteristic.location.point`, $customer) < 5000
RETURN n
```

The canonical GeoJSON for the nested geometry lives inside the parent's JSON blob; only the indexable companion is lifted to the node. Arrays of geometry-bearing values are not yet walked (single-companion-per-array is a deferred design question).

## Expression functions

`st_*` functions match ash_geo / PostGIS signatures so consumer code reads identically across data layers.

| Function | Returns | Pushdown |
|---|---|---|
| `st_contains(a, b)` | boolean — `a` contains `b` (exact, hole-aware) | ✓ indexed bbox prefilter (Cypher) + exact `topo` refinement (in-memory) |
| `st_within(a, b)` | boolean — `a` is within `b` (flipped `st_contains`) | exact `topo`, in-memory |
| `st_intersects(a, b)` | boolean — `a` overlaps `b` (exact, incl. edge crossings) | exact `topo`, in-memory |
| `st_distance(a, b)` | float meters — any geometry ↔ Point (exact) | ✓ inside a comparison (Point attrs); in-memory in `order_by` / `calculate` and for non-Point geometries |
| `st_distance_in_meters(a, b)` | float meters — alias for `st_distance` | ✓ same as `st_distance` |
| `st_dwithin(a, b, distance)` | boolean — within `distance` meters | ✓ Cypher (Point attrs); in-memory for other geometries |
| `st_closest_point(collection, point)` | `%Geo.Point{}` — closest point on the nearest segment (LineString) / nearest vertex (MultiPoint) | in-memory |

```elixir
require Ash.Query

# Service-qualification: which Places contain the customer?
Place |> Ash.Query.filter(st_contains(bounds, ^customer_point)) |> Ash.read!()

# "Near me" — POIs within 5 km
Place |> Ash.Query.filter(st_dwithin(location, ^customer_point, 5_000)) |> Ash.read!()

# Distance comparison (pushed down for Point attributes)
Place |> Ash.Query.filter(st_distance(location, ^customer_point) < 5_000) |> Ash.read!()
```

`st_contains` and `st_intersects` are **exact and hole-aware** — they refine via [`topo`](https://hex.pm/packages/topo) on the actual `%Geo.*{}` rings, not the bounding box. A point in the bbox but outside the ring is correctly excluded; a point in an interior ring (hole) is not contained; a line that crosses a polygon without a vertex inside it correctly intersects. Inside an `Ash.Query.filter`, the `bbSW`/`bbNE` companions drive a cheap indexed `point.withinBBox` **prefilter** in Cypher (over-selecting candidates whose bbox contains the test geometry); the exact `topo` test then runs in-memory over those candidates. A true match always lies within the polygon's bbox, so the prefilter never drops one.

`st_distance` measures **any geometry to a Point** exactly (#279): LineString/MultiLineString use the true closest-point-on-**segment** (not closest-vertex, which overstates the distance for a point near a long edge's midpoint); Polygon/MultiPolygon return `0` when the point is inside (hole-aware) and the nearest-boundary distance otherwise. `st_dwithin` inherits all of this. Distance between two **non-Point** geometries (line↔line, line↔polygon, polygon↔polygon) needs segment-to-segment math and is deferred.

### Distance matches Neo4j's own model

`st_distance` runs two ways — pushed down to Neo4j's native `point.distance` inside a comparison filter, or evaluated in Elixir (`AshNeo4j.Geo.haversine_meters/2`) for `order_by` / `calculate` and for LineString/MultiPoint. **Both deliberately use the same model** so the same query gives the same answer regardless of which path it takes: a spherical haversine on the WGS-84 **equatorial** radius (6 378 137 m) — the radius Neo4j's `point.distance` uses, *not* the mean Earth radius (6 371 000 m) a naive haversine reaches for. The two agree to within ~1 m over a 700 km span. AshNeo4j matches Neo4j's capability here rather than inventing its own — Neo4j's model is the reference because that's what the pushdown executes. (Neo4j's model is spherical, not ellipsoidal; true ellipsoidal distance would differ by a further ~0.1–0.5 %, but matching the pushdown is what keeps results consistent.)

## 3D points (WGS-84-3D) — #270

A point can carry a height. Declare it `:point_z` at `force_srid: 4979` (WGS-84-3D); the value is a `%Geo.PointZ{coordinates: {lng, lat, height}}`:

```elixir
attribute :antenna, AshGeo.GeoJson, constraints: [geo_types: [:point_z], force_srid: 4979]
```

`PointZ` is the OGC/Geo name for the 3D point *shape*; `srid 4979` is the WGS-84-3D *CRS* — orthogonal concerns that pair here (you could also have a cartesian `PointZ`). On disk a `PointZ` stores its canonical GeoJSON at `<attr>.json` (a third coordinate per RFC 7946) and a **native 3D Neo4j POINT** (srid 4979) at `<attr>.point`.

`st_distance` / `st_dwithin` work in 3D — pushed down to Neo4j's native 3D `point.distance` inside a comparison filter, and evaluated in-memory (`AshNeo4j.Geo.haversine_meters_3d/2`) for `order_by` / `calculate`. **Both use the same model** so the same query gives the same answer on either path. Neo4j's 3D geographic distance is *not* a naive `√(ground² + Δh²)`: the great-circle arc is taken at the **mean height** and then combined with the height delta by Pythagoras — `√((arc·(R+h_mean)/R)² + Δh²)` — which AshNeo4j matches to ~0.1 m.

```elixir
require Ash.Query

# towers within 2 km (3D — accounts for height)
Site |> Ash.Query.filter(st_dwithin(antenna, ^candidate_3d, 2_000)) |> Ash.read!()

# rank by true 3D proximity
Site |> Ash.Query.sort({calc(st_distance(antenna, ^candidate_3d), type: :float), :asc}) |> Ash.read!()
```

### Strict 2D/3D evaluation, and the downward projection

Mixing dimensions in one operation is a **hard error**, not a silent result. Neo4j returns `null` for a mixed-CRS `point.distance` / `point.withinBBox` (which then quietly drops rows in a `WHERE`), so AshNeo4j refuses up front with `AshNeo4j.Error.GeoDimensionMismatch` — a 3D value against a 2D attribute, or vice versa.

The only sanctioned bridge is a **downward projection** — collapse the 3D operand to its 2D footprint (OGC `ST_Force2D`) with `AshNeo4j.Geo.force_2d/1`, then evaluate wholly in the 2D world. "Is this 3D antenna inside the 2D coverage area?" is valid *after* the collapse:

```elixir
Place |> Ash.Query.filter(st_contains(coverage_area, ^AshNeo4j.Geo.force_2d(antenna))) |> Ash.read!()
```

There is no `to_3d` — a height cannot be fabricated; supplying one is adding data, an explicit act by the caller, never implicit.

### Not yet (3D Phase 2)

3D **areal/linear** geometries (`PolygonZ`, `LineStringZ`, …) are not supported — writing one raises `AshNeo4j.Error.Unsupported3DGeometry`. Exact 3D containment/distance needs a model the 2D `topo` refinement can't give, and "contains" is naturally a 2D footprint question (project the 3D point and ask in 2D). Tracked for a later slice of #270.

## Holiness via Ash composition

Excluding regions from positive matches — "in this CSA *but not in any exclusion zone*" — is plain Ash composition over the predicates:

```elixir
Place
|> Ash.Query.filter(
  expr(
    st_contains(bounds, ^customer_point) and
    not exists(exclusions, st_contains(bounds, ^customer_point))
  )
)
|> Ash.read!()
```

When exclusions are **independent peer resources** with their own lifecycle, the natural shape is set difference at a common identity (`A EXCEPT UNION(B_i)`) — see `usage-rules/combination-queries.md`.

## Indexes — **indexable, not yet indexed**

The companions are scalar Point properties specifically so they can be indexed via Neo4j's POINT index. AshNeo4j does not create indexes *for* you — index lifecycle is a deliberate operator concern (no migrations, [#45](https://github.com/diffo-dev/ash_neo4j/issues/45)) — but `AshNeo4j.Spatial` builds and runs the right Cypher from a resource + attribute, so you don't hand-encode the label, translation, and companion suffixes:

```elixir
# Point attribute → one `.point` index
AshNeo4j.Spatial.create_index(Place, :location)

# Non-Point geometry → both bbSW and bbNE corner indexes in one call
AshNeo4j.Spatial.create_index(Place, :bounds)

# Nested geometry — [attribute, field...] path into a TypedStruct
AshNeo4j.Spatial.create_index(Place, [:pet, :home])

# Rebuild after a storage-shape change (DROP IF EXISTS + CREATE)
AshNeo4j.Spatial.create_index(Place, :location, recreate: true)
```

`create_index/3` uses `IF NOT EXISTS`, so it's safe to call repeatedly — e.g. from an application start-up task. It returns `{:ok, responses}` (one `%Bolty.Response{}` per index — two for a bbox geometry) or `{:error, reason}`; `drop_index/2` is the symmetric remove. Indexes are schema objects independent of data — clearing nodes never drops them, and they re-populate as nodes are written — so you create them once. `index_statements/3` returns the exact `CREATE` Cypher without touching the database, for review, a migration file, or a dry run:

```elixir
AshNeo4j.Spatial.index_statements(Place, :bounds)
#=> {:ok, [
#=>   "CREATE POINT INDEX place_bounds_bbSW IF NOT EXISTS FOR (n:Place) ON (n.`bounds.bbSW`)",
#=>   "CREATE POINT INDEX place_bounds_bbNE IF NOT EXISTS FOR (n:Place) ON (n.`bounds.bbNE`)"
#=> ]}
```

### Doing it by hand

The function just applies conventions you can also write directly:

```cypher
CREATE POINT INDEX FOR (p:Place) ON (p.`location.point`);
CREATE POINT INDEX FOR (p:Place) ON (p.`bounds.bbSW`);
CREATE POINT INDEX FOR (p:Place) ON (p.`bounds.bbNE`);
```

A **nested** geometry indexes exactly the same way — its promoted companion is a single Neo4j property named by the dotted schema path. For the `:characteristic` TypedStruct attribute above (with a `location` field), the promoted property is `characteristic.location.point`:

```cypher
CREATE POINT INDEX FOR (p:Place) ON (p.`characteristic.location.point`);
```

The dot notation just extends down the schema tree — `<attr>.<field>.point` for one level deep, `<attr>.<field>.<field>.point` for deeper. Each promoted companion is one scalar Point property (backticked for the dots), so it's indexable like any other. A point buried inside a characteristic gets the same indexed `point.distance` / `point.withinBBox` pushdown as a top-level one.

### Property names come from the attribute translation

Index cypher references the **on-disk property name**, not the Ash attribute name. AshNeo4j translates `snake_case` attributes to `camelCase` properties (or whatever `source:` overrides), and the companion suffix (`.point`, `.bbSW`, `.bbNE`) appends to that *translated* name. For `:location` the two happen to coincide (`location.point`), but `:home_location` would be `homeLocation.point` — don't assume attribute name equals property name.

Pull the property name from introspection rather than hard-coding it. `AshNeo4j.Resource.Info.translations/1` returns the attribute → property mapping:

```elixir
iex> AshNeo4j.Resource.Info.translations(Place) |> Keyword.get(:location)
:location

iex> AshNeo4j.Resource.Info.translations(Place) |> Keyword.get(:home_location)
:homeLocation
```

The companion is then `"#{property}.point"` for a Point, `"#{property}.bbSW"` / `"#{property}.bbNE"` for other geometries. For a nested geometry the path is `"#{property}.#{field}.point"`, where `field` is the raw TypedStruct field name (the nested field segments are **not** camelCased — only the top-level attribute goes through translation).

### Sending the index cypher from Elixir

You don't need the Neo4j browser — `AshNeo4j.Cypher.run/2` sends raw Cypher over the same `Bolt` connection the data layer uses (sandbox-aware: it runs inside the test transaction under `AshNeo4j.Sandbox`, and against the live connection in production). Use `IF NOT EXISTS` so it's safe to run repeatedly, e.g. from an application start-up task or a one-off mix task:

```elixir
property = AshNeo4j.Resource.Info.translations(Place) |> Keyword.get(:location)

AshNeo4j.Cypher.run(
  "CREATE POINT INDEX place_location IF NOT EXISTS FOR (p:Place) ON (p.`#{property}.point`)"
)

# nested — the `:characteristic` attribute's `location` field
char_property = AshNeo4j.Resource.Info.translations(Place) |> Keyword.get(:characteristic)

AshNeo4j.Cypher.run(
  "CREATE POINT INDEX place_char_location IF NOT EXISTS FOR (p:Place) ON (p.`#{char_property}.location.point`)"
)
```

`run/2` returns `{:ok, %Bolty.Response{}} | {:error, reason}`. Index creation is idempotent with `IF NOT EXISTS`, so a startup hook that creates the indexes your queries rely on is a reasonable pattern — AshNeo4j just doesn't do it *for* you (it has no migrations, and index lifecycle is a deliberate operator concern).

> `AshNeo4j.Spatial.create_index/3` (above) does all of this for you — resolving the label, translation, and companion suffix, including the two-corner case for bbox geometries ([#275](https://github.com/diffo-dev/ash_neo4j/issues/275)). Compose the property name from `translations/1` only when you need the raw Cypher yourself.

The GeoJSON `STRING` and any vertex data are never indexable for spatial queries — Neo4j doesn't index points inside arrays or strings. All spatial WHERE clauses route through the scalar Point companions, which is why they exist.

## Migrating from 0.7.0

0.7.0 shipped `AshNeo4j.Type.Point` (a `%Bolty.Types.Point{}` at the boundary, stored as a native Point) and `AshNeo4j.Type.Box` (a `%Box{sw, ne}`, stored as a 4-Point array). Both are removed.

- **Attribute declarations**: `AshNeo4j.Type.Point` → `AshGeo.GeoJson, constraints: [geo_types: [:point], force_srid: 4326]`; `AshNeo4j.Type.Box` → `AshGeo.GeoJson, constraints: [geo_types: [:polygon], force_srid: 4326]` (Box was always proto-Polygon; axis-aligned validation is now an application-layer concern).
- **Values**: `Bolty.Types.Point.create(:wgs_84, lng, lat)` → `%Geo.Point{coordinates: {lng, lat}, srid: 4326}`; `%AshNeo4j.Type.Box{sw, ne}` → `%Geo.Polygon{coordinates: [ring], srid: 4326}`.
- **Stored data**: the on-disk shape changed (native Point at `<attr>` → `<attr>.point` + `<attr>.json`; Box's 4-Point array → `<attr>.json` + `bbSW`/`bbNE`). Existing 0.7.0 spatial nodes need re-creation or a one-shot migration cypher to move the data into the new property names. AshNeo4j ships no automatic migration (it has no migrations by design).

## Limitations

- **WGS-84 2D, plus WGS-84-3D points** (`:point_z`, srid 4979 — #270). 3D areal/linear geometries (`PolygonZ`, …) are not yet supported; other CRSs are out of scope.
- **Mixed 2D/3D is a hard error** (`GeoDimensionMismatch`) — bridge with `AshNeo4j.Geo.force_2d/1` (3D→2D footprint); there is no implicit 2D→3D lift.
- **`st_distance` in `order_by` / `calculate` is in-memory.** Fine at NBN scale; pushdown for those contexts is future work.
- **`st_distance` between two non-Point geometries is not yet implemented** (line↔line, line↔polygon, polygon↔polygon — needs segment-to-segment math; returns `:unknown`). Any geometry **to a Point** is exact (closest-point-on-segment for lines, nearest-boundary for polygons).
- **`st_intersects` has no Cypher prefilter** — it's exact but in-memory only; a bbox-overlap prefilter via the companions is tractable and deferred.
- **Arrays of geometry-bearing values aren't recursively walked** for companion promotion yet.
- **Index lifecycle is the operator's responsibility** (see above).
- **Upstream workarounds in place**: list-form `geo_types` ([ash_geo#13](https://github.com/bcksl/ash_geo/pull/13)), nested-geo read decoding ([ash_geo#14](https://github.com/bcksl/ash_geo/pull/14)), and strict RFC 7946 encoding ([felt/geo#250](https://github.com/felt/geo/issues/250)). These are local until the upstream fixes release.
