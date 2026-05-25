<!--
SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Spatial types and expressions

AshNeo4j has first-class spatial support: `Point` and `Box` as Ash attribute types, plus `st_*` expression functions matching ash_geo / PostGIS signatures exactly. Predicates push down to native Cypher (`point.distance`, `point.withinBBox`) wherever possible, falling back to in-memory evaluation otherwise. WGS-84 2D only in this release.

## Types

### `AshNeo4j.Type.Point`

A geographic point — longitude/latitude in WGS-84. Wraps `Bolty.Types.Point`; stored as a native Neo4j Point property.

```elixir
attributes do
  attribute :location, AshNeo4j.Type.Point, public?: true
end

# Construction
location = Bolty.Types.Point.create(:wgs_84, 151.2093, -33.8688)  # Sydney

Place |> Ash.create!(%{name: "Sydney CBD", location: location})
```

### `AshNeo4j.Type.Box`

A straight-sided axis-aligned bounding box. Ergonomic struct `%Box{sw, ne}` with two corners.

```elixir
attributes do
  attribute :bounds, AshNeo4j.Type.Box, public?: true
end

bounds = %AshNeo4j.Type.Box{
  sw: Bolty.Types.Point.create(:wgs_84, 151.0, -34.0),
  ne: Bolty.Types.Point.create(:wgs_84, 151.5, -33.5)
}

Place |> Ash.create!(%{name: "Sydney bbox", bounds: bounds})
```

## Storage shape

A Box (and a future Polygon) is stored on the node as **two parts**:

- The **vertex array** — for a Box, the 4 corners CCW from SW (`[sw, se, ne, nw]`) per the GeoJSON convention. Property name matches the attribute (`:bounds` → `bounds`).
- **Four scalar Point companion properties** — `<prop>.bbSW`, `<prop>.bbSE`, `<prop>.bbNE`, `<prop>.bbNW` — written automatically by the data layer for indexed spatial queries.

You never declare the companion properties; the data layer manages them. They appear on the node automatically when you write a Box-valued attribute.

For an attribute named `:bounds`, a created node has properties:

```
bounds         = [Point, Point, Point, Point]
bounds.bbSW    = Point
bounds.bbSE    = Point
bounds.bbNE    = Point
bounds.bbNW    = Point
```

The dotted companion names are backticked in any Cypher you write directly (`` n.`bounds.bbSW` ``).

## Expression functions

All six functions match ash_geo / PostGIS signatures exactly so consumer code reads identically across data layers.

| Function | Returns | Pushdown |
|---|---|---|
| `st_contains(a, b)` | boolean — `a` contains `b` | ✓ Cypher (box-point, box-box) |
| `st_within(a, b)` | boolean — `a` is within `b` (flipped `st_contains`) | in-memory |
| `st_intersects(a, b)` | boolean — `a` overlaps `b` | in-memory (box-box) |
| `st_distance(a, b)` | float meters | ✓ inside a comparison; in-memory in `order_by` / `calculate` |
| `st_distance_in_meters(a, b)` | float meters — alias for `st_distance` | ✓ same as `st_distance` |
| `st_dwithin(a, b, distance)` | boolean — `a` and `b` are within `distance` meters | ✓ Cypher |

### Examples

```elixir
require Ash.Query

# Service-qualification: which Places contain the customer?
Place
|> Ash.Query.filter(st_contains(bounds, ^customer_point))
|> Ash.read!()

# "Near me" — POIs within 5 km of the customer
Place
|> Ash.Query.filter(st_dwithin(location, ^customer_point, 5_000))
|> Ash.read!()

# Distance comparison (pushed down)
Place
|> Ash.Query.filter(st_distance(location, ^customer_point) < 5_000)
|> Ash.read!()

# Bounding box overlap (in-memory)
Place
|> Ash.Query.filter(st_intersects(bounds, ^search_box))
|> Ash.read!()
```

## Holiness via Ash composition

Excluding regions from positive matches — "in this CSA *but not in any exclusion zone*" — is plain Ash composition over the predicates. No special construct needed:

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

This works when `exclusions` is an Ash relationship from `Place` to the exclusion resource (parent/child shape).

When exclusions are **independent peer resources** with their own lifecycle (e.g., a regulatory regime where blocking areas are tracked separately, not as children of the containing area), the natural shape is set difference at a common identity (`A EXCEPT UNION(B_i)`). That requires combination-query support in the data layer — see [#10](https://github.com/diffo-dev/ash_neo4j/issues/10).

## Indexes — **indexable, not yet indexed**

The bbox companions are stored as **scalar Point properties** specifically so they can be indexed via Neo4j's POINT index. AshNeo4j does not create or manage these indexes — operators who want the speed run them themselves:

```cypher
CREATE POINT INDEX ON :Place(`bounds.bbSW`);
CREATE POINT INDEX ON :Place(`bounds.bbNE`);
```

The vertex array (`n.bounds`) is never indexable — Neo4j doesn't index points inside arrays. All spatial WHERE clauses route through the scalar companions, which is why they exist.

## Limitations

- **WGS-84 2D only.** Other CRSs (Cartesian, WGS-84 3D) raise at cast time.
- **`st_distance` in `order_by` / `calculate` is in-memory.** Pushdown for those contexts is future work; fine at NBN scale.
- **Box-only containment.** Real polygon containment is tracked in [#267](https://github.com/diffo-dev/ash_neo4j/issues/267); use Box approximations until then.
- **Index lifecycle is the operator's responsibility** (see above).
- **Antimeridian-crossing geometries** are detected at cast and rejected. Future work.
