<!--
SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Spatial types and expressions

AshNeo4j stores geometries using [`ash_geo`](https://hex.pm/packages/ash_geo) types at the Ash boundary and `st_*` expression functions matching ash_geo / PostGIS signatures. Predicates push down to native Cypher (`point.distance`, `point.withinBBox`) where possible, falling back to in-memory evaluation otherwise. WGS-84 2D only in this release.

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
| `st_contains(a, b)` | boolean — `a` contains `b` | ✓ Cypher (polygon-point, polygon-polygon via bbox companions) |
| `st_within(a, b)` | boolean — `a` is within `b` (flipped `st_contains`) | in-memory |
| `st_intersects(a, b)` | boolean — `a` overlaps `b` | in-memory |
| `st_distance(a, b)` | float meters | ✓ inside a comparison (Point attrs); in-memory in `order_by` / `calculate` and for line/multipoint |
| `st_distance_in_meters(a, b)` | float meters — alias for `st_distance` | ✓ same as `st_distance` |
| `st_dwithin(a, b, distance)` | boolean — within `distance` meters | ✓ Cypher (Point attrs) |
| `st_closest_point(collection, point)` | `%Geo.Point{}` — nearest vertex from a LineString/MultiPoint | in-memory |

```elixir
require Ash.Query

# Service-qualification: which Places contain the customer?
Place |> Ash.Query.filter(st_contains(bounds, ^customer_point)) |> Ash.read!()

# "Near me" — POIs within 5 km
Place |> Ash.Query.filter(st_dwithin(location, ^customer_point, 5_000)) |> Ash.read!()

# Distance comparison (pushed down for Point attributes)
Place |> Ash.Query.filter(st_distance(location, ^customer_point) < 5_000) |> Ash.read!()
```

Predicate pushdown for Polygon-shaped containment uses the `bbSW`/`bbNE` companions — exact for axis-aligned polygons, an over-approximation for general polygons (true point-in-polygon refinement is [#267](https://github.com/diffo-dev/ash_neo4j/issues/267)). `st_distance`/`st_intersects` on LineString/MultiPoint use closest-vertex / vertex-in-bbox approximations; documented per function moduledoc.

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

The companions are scalar Point properties specifically so they can be indexed via Neo4j's POINT index. AshNeo4j does not create or manage these indexes — operators who want the speed run them themselves:

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

> A convenience function that builds this Cypher from the resource module + attribute name (resolving the label, translation, and companion suffix for you, including the two-corner case for bbox geometries) is tracked in [#275](https://github.com/diffo-dev/ash_neo4j/issues/275). Until it lands, compose the property name from `translations/1` as above.

The GeoJSON `STRING` and any vertex data are never indexable for spatial queries — Neo4j doesn't index points inside arrays or strings. All spatial WHERE clauses route through the scalar Point companions, which is why they exist.

## Migrating from 0.7.0

0.7.0 shipped `AshNeo4j.Type.Point` (a `%Bolty.Types.Point{}` at the boundary, stored as a native Point) and `AshNeo4j.Type.Box` (a `%Box{sw, ne}`, stored as a 4-Point array). Both are removed.

- **Attribute declarations**: `AshNeo4j.Type.Point` → `AshGeo.GeoJson, constraints: [geo_types: [:point], force_srid: 4326]`; `AshNeo4j.Type.Box` → `AshGeo.GeoJson, constraints: [geo_types: [:polygon], force_srid: 4326]` (Box was always proto-Polygon; axis-aligned validation is now an application-layer concern).
- **Values**: `Bolty.Types.Point.create(:wgs_84, lng, lat)` → `%Geo.Point{coordinates: {lng, lat}, srid: 4326}`; `%AshNeo4j.Type.Box{sw, ne}` → `%Geo.Polygon{coordinates: [ring], srid: 4326}`.
- **Stored data**: the on-disk shape changed (native Point at `<attr>` → `<attr>.point` + `<attr>.json`; Box's 4-Point array → `<attr>.json` + `bbSW`/`bbNE`). Existing 0.7.0 spatial nodes need re-creation or a one-shot migration cypher to move the data into the new property names. AshNeo4j ships no automatic migration (it has no migrations by design).

## Limitations

- **WGS-84 2D only.** Set `force_srid: 4326`; other CRSs are out of scope this release.
- **`st_distance` in `order_by` / `calculate` is in-memory.** Fine at NBN scale; pushdown for those contexts is future work.
- **Polygon containment is bbox-approximate.** Exact for axis-aligned polygons; true point-in-polygon is [#267](https://github.com/diffo-dev/ash_neo4j/issues/267).
- **LineString / MultiPoint distance & intersection are vertex approximations** (closest-vertex, vertex-in-bbox). Documented per function.
- **Arrays of geometry-bearing values aren't recursively walked** for companion promotion yet.
- **Index lifecycle is the operator's responsibility** (see above).
- **Upstream workarounds in place**: list-form `geo_types` ([ash_geo#13](https://github.com/bcksl/ash_geo/pull/13)), nested-geo read decoding ([ash_geo#14](https://github.com/bcksl/ash_geo/pull/14)), and strict RFC 7946 encoding ([felt/geo#250](https://github.com/felt/geo/issues/250)). These are local until the upstream fixes release.
