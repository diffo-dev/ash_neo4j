<!-- 
SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](Https://conventionalcommits.org) for commit guidelines.

<!-- changelog -->

## [Unreleased]

### Breaking Changes

* **Spatial storage rearchitecture** (#274) — the spatial surface introduced in 0.7.0 is replaced. The `AshNeo4j.Type.Point` and `AshNeo4j.Type.Box` modules are **removed**; spatial attributes now use [`ash_geo`](https://hex.pm/packages/ash_geo) types and carry [`%Geo.*{}`](https://hex.pm/packages/geo) structs. `Bolty.Types.Point` no longer appears at the Ash boundary (it was a driver-layer type leaking through). Migration:
  - `attribute :loc, AshNeo4j.Type.Point` → `attribute :loc, AshGeo.GeoJson, constraints: [geo_types: [:point], force_srid: 4326]`
  - `attribute :b, AshNeo4j.Type.Box` → `attribute :b, AshGeo.GeoJson, constraints: [geo_types: [:polygon], force_srid: 4326]` (Box was always proto-Polygon; axis-aligned validation is now an application-layer concern)
  - values: `Bolty.Types.Point.create(:wgs_84, lng, lat)` → `%Geo.Point{coordinates: {lng, lat}, srid: 4326}`; `%AshNeo4j.Type.Box{sw, ne}` → `%Geo.Polygon{coordinates: [ring], srid: 4326}`
  - **on-disk shape changed**: Point's native Point moves from `<attr>` to `<attr>.point` and gains a `<attr>.json` canonical; Box's 4-Point array becomes `<attr>.json` + `<attr>.bbSW`/`<attr>.bbNE`. Existing 0.7.0 spatial nodes need re-creation or a one-shot migration cypher (AshNeo4j ships no migrations by design).

  Adds `ash_geo ~> 0.3` as a runtime dependency (clean — `jason`/`geo`/`ash`; the PostGIS-flavoured deps are test-only in ash_geo).

### Features

* **Full GeoJSON geometry surface** (#274) — `AshGeo.GeoJson` / `AshGeo.GeoAny` attributes support all RFC 7946 geometry types: `Point`, `LineString`, `Polygon`, `MultiPoint`, `MultiLineString`, `MultiPolygon`. The data layer detects geometry values (classification `:geo` in `TypeClassifier`) and stores them as a canonical RFC 7946 GeoJSON `STRING` at `<attr>.json` plus indexable scalar Point companions — native `<attr>.point` for Point (preserving `point.distance`/`point.withinBBox` pushdown), `<attr>.bbSW`/`<attr>.bbNE` bounding-box corners for everything else. On-disk GeoJSON is strict RFC 7946 (no `crs` member, `bbox` member included) so any GIS tool can ingest it directly.

* **Recursive geo-promotion** (#274) — a geometry nested inside another attribute (an `Ash.TypedStruct` field, embedded resource, map) has its indexable companion promoted to a node-level property at the dotted path (`<attr>.<field>.point` etc.), even though the parent value stores as a single JSON blob. A location buried inside a characteristic is indexable via `point.distance(n.`characteristic.location.point`, …)`. The data layer walks the value tree on write (`geo_walk/2`) and round-trips the nested geometry on read.

* **`st_closest_point`** (#274) — new `Ash.Query.Function` returning the nearest vertex (`%Geo.Point{}`) from a `LineString` or `MultiPoint` to a target point. In-memory.

* **`AshNeo4j.Spatial` index helpers** (#275) — `create_index/3` / `drop_index/2` build and run the POINT index Cypher backing spatial pushdown from a resource module + attribute name, resolving the Neo4j label, the attribute→property translation, and the companion suffix convention (`.point` for a Point; both `.bbSW`/`.bbNE` for any other geometry, in one call). Nested geometries take a `[attribute, field…]` path (`create_index(Place, [:pet, :home])`) and resolve the dotted property by walking the `Ash.TypedStruct` fields. `create_index/3` is idempotent (`CREATE … IF NOT EXISTS`), takes `recreate: true` (DROP + CREATE) for storage-shape changes, and `name:` to override the derived index name. `index_statements/3` returns the exact Cypher without touching the database, for review or a dry run. Consistent with the "no migrations, index lifecycle is the operator's concern" stance (#45) — an ergonomic tool you call, not automatic behaviour.

* **`AshNeo4j.worlds/1` — N-world projection** (#273, **exploratory**) — a Neo4j node carries labels for *every* `(Domain, Resource)` world it participates in, but an Ash read returns only the queried world's struct. `worlds/1` projects a read record's labels (already on `__metadata__.labels`) back to the loadable resource modules — `[{domain, resource}, …]` ordered **outermost-first** — so a consumer can recover the outer type(s) of a polymorphic node for cross-domain late binding ([diffo#172](https://github.com/diffo-dev/diffo/issues/172)) without dropping to Cypher. An outer world contains the inner worlds and adds detail, so it carries more labels (more labels = more nuanced = more outer). Resolution is dynamic against loaded modules (no registry): a candidate is a loaded `AshNeo4j.DataLayer` resource whose own labels are a subset of the node's, the outermost (most-nuanced) is kept per domain, and the loaded-resource index is cached in `:persistent_term`. Labels that don't resolve to a loaded module are left unknown — omitted, never coerced. Returns `[]` for a non-AshNeo4j record. Pre-1.0 and may change — shipped to learn its shape from real downstream use.

### Improvements

* **In-memory distance matches Neo4j's `point.distance`** (#274) — `st_distance` / `st_dwithin` push down to Neo4j's native `point.distance` inside comparison filters but evaluate in Elixir elsewhere (`order_by`, `calculate`, LineString/MultiPoint). Both now use the same model — a spherical haversine on the WGS-84 **equatorial** radius (6 378 137 m), the radius Neo4j uses, not the mean Earth radius (6 371 000 m) — so the two paths agree to within ~1 m over 700 km rather than diverging by ~0.11 % (≈800 m). Single source of truth `AshNeo4j.Geo.haversine_meters/2`, shared by `st_distance` and `st_closest_point`; a sandbox test asserts the paths stay in step.

* **`st_*` expression functions extended** (#274) — `st_distance` / `st_dwithin` / `st_intersects` / `st_contains` / `st_within` now operate on `%Geo.*{}` argument shapes across the full geometry surface. Pushdown gating reads the attribute's `geo_types` constraint rather than the (now-removed) type-module identity.

* **Exact, hole-aware polygon predicates** (#267) — `st_contains` and `st_intersects` refine via [`topo`](https://hex.pm/packages/topo) on the actual `%Geo.*{}` rings, replacing the bbox approximation. A point in the bounding box but outside the ring is correctly excluded; a point in an interior ring (hole) is not contained; a LineString that crosses a Polygon **without** a vertex inside it correctly intersects. Inside `Ash.Query.filter`, `st_contains` keeps the indexed `point.withinBBox` bbox **prefilter** in Cypher and runs the exact `topo` test in-memory over the candidates (a true match always lies within the bbox, so the prefilter never drops one). Adds `topo ~> 1.0` runtime dep.

* **Exact geometry-to-Point distance** (#279) — `st_distance` (and `st_dwithin`, which delegates to it) now measures **any geometry to a Point** exactly: LineString/MultiLineString use the true closest-point-on-**segment** instead of closest-vertex (the old approximation could overstate a mid-edge proximity by tens of kilometres — e.g. 78.7 km reported where the perpendicular distance is 55.7 km), and Polygon/MultiPolygon return `0` when the point is inside (hole-aware via `topo`) or the nearest-boundary distance otherwise. `st_closest_point` likewise returns the closest point on the nearest segment of a LineString (an interior edge point, not just a vertex). New `AshNeo4j.Geo.point_segment_meters/3` / `closest_point_on_segment/3` / `min_segment_meters/2` primitives (local equirectangular projection to find the closest point, haversine for the distance). Distance between two non-Point geometries is still deferred. Also confirms MultiLineString — the sixth RFC 7946 geometry — round-trips through storage and works across the predicates, and extends `st_contains` to accept LineString / MultiLineString containees.

* **`AshNeo4j.GeoJson`** (#274) — RFC 7946 encoder/decoder wrapping `geo`; strips the obsolete `crs` member (which `geo` emits when `srid` is set — see [felt/geo#250](https://github.com/felt/geo/issues/250)), injects the `bbox` member, key-sorts via `AshNeo4j.Util.json_encode`. `Util.to_json_safe`/`json_decode` gained symmetric Geo handling so geometries survive nesting inside JSON-stored types. Local workarounds for [ash_geo#13](https://github.com/bcksl/ash_geo/pull/13) (bare-atom `geo_types` formatter crash) and [ash_geo#14](https://github.com/bcksl/ash_geo/pull/14) (`cast_stored` map handling) are in place pending those upstream fixes.

## [v0.7.0](https://github.com/diffo-dev/ash_neo4j/compare/v0.6.0...v0.7.0) (2026-05-25)

### Features

* **Spatial types and `st_*` expressions** (#45) — first-class WGS-84 2D spatial support. New attribute types `AshNeo4j.Type.Point` (native Neo4j Point) and `AshNeo4j.Type.Box` (axis-aligned bounding box, 4-vertex straight-sided polygon on disk). Six `Ash.Query.Function` modules matching ash_geo / PostGIS signatures: `st_contains` (box-point, box-box), `st_within`, `st_intersects`, `st_distance` (point-point, with comparison pushdown), `st_distance_in_meters` (alias), `st_dwithin` (point-point). Predicates push down to native Cypher (`point.distance`, `point.withinBBox`) wherever possible; in-memory `evaluate/1` is the correctness fallback. Box's on-disk storage uses a 4-Point vertex array plus 4 scalar bbox-corner companion properties (`<prop>.bbSW/.bbSE/.bbNE/.bbNW`) written by a generic `companions/1` callback on the Type module — the same shape future Polygon support ([#267](https://github.com/diffo-dev/ash_neo4j/issues/267)) will use, so no data migration when Polygon lands. The bbox companions are scalar Point properties specifically to be indexable via Neo4j's POINT index — storage is **indexable, not yet indexed** (operators run `CREATE POINT INDEX` themselves; lifecycle management is future work). Documentation in `usage-rules/spatial.md`. Requires `bolty >= 0.0.13` for native Point property serialisation ([bolty#32](https://github.com/diffo-dev/bolty/issues/32)).

* **Combination queries** (#10) — support for all five `Ash.Query.Combination` types (`:base`, `:union`, `:union_all`, `:intersect`, `:except`). Combinations of only `:union` or only `:union_all` push down to a single Cypher `CALL { … UNION/UNION ALL … } WITH s OPTIONAL MATCH (s)-[r]-(d) RETURN s, r, d` block, with per-branch parameter prefixing to avoid name collisions. Combinations involving `:intersect`, `:except`, or mixed union types take an in-memory orchestration path — each branch runs returning just node ids (`id(s) AS sid`), the set operation is computed in Elixir over `MapSet`s, then a final `MATCH WHERE id(s) IN $ids` fetches the keep-set with the standard OPTIONAL MATCH enrichment. Cypher has no native `INTERSECT`/`EXCEPT`; the in-memory implementation is the honest answer. Documentation in `usage-rules/combination-queries.md`. New `AshNeo4j.Cypher.Query` builders: `branch_node_read/3`, `branch_node_read_ids/3`, `combination_block/2`, `node_read_by_ids/2`; new `param_prefix:` opt on `node_read_filtered/3` and `build_conditions/3`. New `AshNeo4j.Cypher.Call` clause type.

## [v0.6.0](https://github.com/diffo-dev/ash_neo4j/compare/v0.5.1...v0.6.0) (2026-05-19)

### Breaking Changes

* **Introspection API renamed** (#105) — `AshNeo4j.DataLayer.Info` and `AshNeo4j.DataLayer.Domain.Info` are now generated by `Spark.InfoGenerator`. AshNeo4j now declares a direct `spark >= 2.7.0` dependency to guarantee availability. All functions follow the InfoGenerator convention: `neo4j_label/1` returns `{:ok, value} | :error`; `neo4j_label!/1` returns the value or raises; list options (`relate`, `guard`, `skip`) always return the list via the `!` variant. Previous hand-rolled helpers (`label/1`, `relate/1`, `guard/1`, `skip/1`) are removed.

### Features

* **Domain fragment label** (#261) — domains can declare a cross-domain graph label via `AshNeo4j.DataLayer.Domain` (`use Ash.Domain, extensions: [AshNeo4j.DataLayer.Domain]` with `neo4j do label :MyLabel end`). The fragment label is written as an additional Neo4j node label on CREATE, enabling polymorphic graph traversals across domains. Exposed via `ResourceInfo.domain_fragment_label/1` and included in `ResourceInfo.all_labels/1` and `ResourceInfo.mapping/1`.

### Bug Fixes

* **`belongs_to` FK always nil after read** (#258) — `belongs_to` source attributes (e.g. `specification_id`) were correctly populated on create but lost on any subsequent read. The enrichment step now correctly extracts the FK from the destination node returned by the OPTIONAL MATCH traversal when the source resource uses a fragment-inherited relationship whose destination lives in a different domain.

* **Domain fragment label dropped on Ash 3.25+** — `ResourceInfo.all_labels/1` was returning the compile-time persisted label list, which is baked before the domain extension compiles under Ash 3.25's updated compilation order, causing the domain fragment label to be silently omitted. `all_labels/1` now always computes dynamically from the individual label accessors, consistent with how `mapping/1` already worked.

### Improvements

* **Scalar filter pushdown for aggregates** (#253) — filtered aggregates whose filter consists entirely of scalar `==` equality predicates on non-embedded destination attributes now push a `WHERE d.prop = $val` clause directly into Cypher, avoiding full destination record loading in Elixir. Complex filters (OR, embedded fields, non-equality operators) continue to use the Elixir-side path introduced in #252.

## [v0.5.1](https://github.com/diffo-dev/ash_neo4j/compare/v0.5.0...v0.5.1) (2026-05-10)

### Improvements

* **Documentation** (#249) — ex_doc configuration overhauled: extras reorganised with titled entries, module groups defined for AshNeo4j, Introspection, Cypher, Utilities and Internals, Livebook added to How To, CHANGELOG included in About AshNeo4j, maintainer contact updated.

### Bug Fixes

* **Aggregate filters honoured** (#252) — filters declared via `filter expr(...)` on aggregate definitions were silently dropped. Filtered aggregates now load full destination records in Elixir and apply `Ash.Filter.Runtime.filter_matches/3` per source group before reducing. The fast Cypher push-down path is preserved for unfiltered aggregates.

* **Aggregate names with `?` suffix** (#251) — aggregate names following the Elixir predicate convention (e.g. `exists :cvc_defined?, :characteristics`) caused Neo4j to reject the generated Cypher with an invalid identifier error. Column aliases are now backtick-quoted, allowing any valid Elixir atom as an aggregate name.

## [v0.5.0](https://github.com/diffo-dev/ash_neo4j/compare/v0.4.1...v0.5.0) (2026-05-08)

### Features

* **Aggregates** — full support for `:count`, `:exists`, `:sum`, `:avg`, `:min`, `:max`, `:first`, `:list` aggregate kinds, declared in the standard Ash `aggregates` block. Aggregates are executed as Cypher `OPTIONAL MATCH` traversals; single-hop and multi-hop relationship paths are both supported.
* **Aggregates on embedded/JSON-type fields** — when `field:` points to an attribute stored as JSON (`Ash.TypedStruct`, `Ash.Type.NewType`, embedded resources, `Ash.Type.Map`, etc.) AshNeo4j collects raw JSON from Neo4j and deserializes in Elixir. `:list` and `:first` return fully-typed structs; `:sum`/`:avg`/`:min`/`:max` work on directly comparable values.
* **Expression aggregates (`expr:`)** — programmatic aggregate API (`Ash.aggregate/3`) accepts `expr:` to aggregate over a sub-field of an embedded struct or any Ash expression, without needing to elevate the field. Fetches full destination records and evaluates expressions in Elixir.
* **Expression calculations** — `calculate :name, :type, expr(...)` declarations are now evaluated in Elixir after records are loaded. Supports load (`Ash.load!`), filter (`Ash.Query.filter`), and sort (`Ash.Query.sort`). Embedded struct fields work directly via `get_path` — no elevation needed.

### Improvements

* Cypher query struct family extended; `Neo4jHelper` refactored to use it
* Calculation-based filter predicates are excluded from Cypher WHERE and evaluated in-memory via `Ash.Filter.Runtime`
* Calculation-based sort terms are applied in Elixir after records are loaded

## [v0.4.1](https://github.com/diffo-dev/ash_neo4j/compare/v0.4.0...v0.4.1) (2026-05-06)

### What's Changed
* fix in_transaction? by @matt-beanland in https://github.com/diffo-dev/ash_neo4j/pull/226
* fixed sandbox and non-sandbox paths by @matt-beanland in https://github.com/diffo-dev/ash_neo4j/pull/227
* fix unhandled throws by @matt-beanland in https://github.com/diffo-dev/ash_neo4j/pull/228

## [v0.4.0](https://github.com/diffo-dev/ash_neo4j/compare/v0.3.1...v0.4.0) (2026-05-01)

### Features:
* real Neo4j transactions via `Bolty.transaction` — `can?(_, :transact)` now advertised, rollback genuinely aborts the database transaction
* `AshNeo4j.Sandbox` — test isolation adapter analogous to `Ecto.Adapters.SQL.Sandbox`, enabling safe parallel test execution with `async: true`

### Improvements:
* silenced spurious runtime `Logger.warning` calls that fired on normal OPTIONAL MATCH traversal
* full test suite parallelised with `async: true`

## [v0.3.1](https://github.com/diffo-dev/ash_neo4j/compare/v0.3.0...v0.3.1) (2026-04-23)

This release changes the storage type for Ash.Type.DateTime, Ash.Type.UtcDateTime and Ash.Type.UtcDateTimeUsec

### What's Changed
* use native neo4j 5.x datetime by @matt-beanland

## [v0.3.0](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.15...v0.3.0) (2026-04-18)

This release changes the storage type for most types. Ash.Type dump_to_native/cast_stored are used where possible.T
String.Chars is no longer required and JSON blobs/Base64 are employed. Native Neo4j types are used except for datetime, instead we use ISO8601 strings to work around Neo4j 5.x incompatibility. There is no data migration supported.

### What's Changed
* 196 remove need for structs to implement stringchars by @matt-beanland in https://github.com/diffo-dev/ash_neo4j/pull/197
* reduced advertised capability, fixed calculations by @matt-beanland in https://github.com/diffo-dev/ash_neo4j/pull/198
* refactored transformers as persisters, split DataLayer and Resource Info by @matt-beanland in https://github.com/diffo-dev/ash_neo4j/pull/201
* updated deps and reinstated keyword tests by @matt-beanland in https://github.com/diffo-dev/ash_neo4j/pull/204
* fixed persister and improved verifier to verify all labels by @matt-beanland in https://github.com/diffo-dev/ash_neo4j/pull/205
* added encoding test and fixed json_encode for map by @matt-beanland in https://github.com/diffo-dev/ash_neo4j/pull/207
* added defensive casting, returning error tuple by @matt-beanland in https://github.com/diffo-dev/ash_neo4j/pull/209
* expression calculations in memory by @matt-beanland in https://github.com/diffo-dev/ash_neo4j/pull/210

## [v0.2.15](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.14...v0.2.15) (2026-03-19)

### Fixes

* fix domain label incorrect

## [v0.2.14](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.13...v0.2.14) (2026-03-19)

### Fixes

* fix relationship enrichment inconsistent across neo4j versions

## [v0.2.13](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.12...v0.2.13) (2026-03-12)

### Features

* translate using attribute source (translate DSL removed)
* nodes are also labelled with domain label

### Fixes

* fixed dates and times not native

### Maintenance

* uses bolty at https://github.com/diffo-dev/bolty, a reluctant fork of boltx
* updated deps and tool versions
* improved info documenation

## [v0.2.12](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.11...v0.2.12) (2025-11-18)

### Features

* 173 relationship source attribute filtering by @matt-beanland in #174

### Maintenance

* added deep wiki badge by @matt-beanland in #171

## [v0.2.11](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.10...v0.2.11) (2025-10-13)

### Features

* REUSE compliant

### Fixes

* updated ash dependency for CVE-2025-48043 fix

## [v0.2.10](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.9...v0.2.10) (2025-09-09)

### Maintenance

* fixed update on_lookup relate on has_many exclusivity

## [v0.2.9](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.8...v0.2.9) (2025-08-16)

### Maintenance

* fixed Ash.Error.Unknown when reading structs embedded in structs

## [v0.2.8](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.7...v0.2.8) (2025-08-14)

### Features

* relate destination node label
* independent relationships
* simplified dsl

### Maintenance

* fixed unexpected empty query result
* fixed has_many enrichment incorrect cypher
* fixed create with multiple relationships doesn't relate nodes

## [v0.2.7](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.6...v0.2.7) (2025-08-03)

### Features

* relates node cypher avoids cartesian product warning

### Maintenance

* fixed Ash.Error.Unknown no result to unrelate nodes
* fixed create or update belongs_to on same resoruce adds rather than replaces
* fixed Ash.Error.Unknown no case clause matching on update
* fixed guard edge label regex
* fixed sorting not working
* fixed nested calculations with references are nil

## [v0.2.6](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.5...v0.2.6) (2025-07-25)

### Maintenance

* fixed nested calculations with references are nil
* fixed cypher error when filtering on atom type
* fixed Ash.Error.Unknown when a delete is guarded
* fixed Ash.Error.Unknown invalid filter statement provided

## [v0.2.5](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.4...v0.2.5) (2025-07-21)

### Features:

* guard against destroy
* improved has_one and belongs_to enrichment
* improved logging

### Maintenance

* fixed destroy should fail when destination has allow_nil?: false

## [v0.2.4](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.3...v0.2.4) (2025-07-16)

### Features:

* support AshStateMachine
* improved enrichment
* query on relationship attribute
* create with multiple relationships

### Maintenance

* fixed Ash.Error.Unknown no function matching clause in AshNeo4j.Cypher.expression/4

## [v0.2.3](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.2...v0.2.3) (2025-07-10)

### Features:

* expression calculations
* unloaded attributes are Ash.NotLoaded
* improved metadata
* improved relate error messages
* improved relate verification

## [v0.2.2](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.1...v0.2.2) (2025-06-26)

### Maintenance:

* refactored tests
* fixed Ash.Error.Unknown when filtering using contains
* fixed Ash.Error.Unknown in datalayer when relate not defined

## [v0.2.1](https://github.com/diffo-dev/ash_neo4j/compare/v0.2.0...v0.2.1) (2025-06-17)

### Features:

* many to many relationship (back to back has_many)
* has one relationship

## [v0.2.0](https://github.com/diffo-dev/ash_neo4j/compare/v0.1.6...v0.2.0) (2025-06-05)

### Features:

* improved BoltxHelper
* create relate
* livebook

## [v0.1.6](https://github.com/diffo-dev/ash_neo4j/compare/v0.1.5...v0.1.6) (2025-06-02)

### Features:

* embedded resources
* nil attributes
* nil relationship attributes

## [v0.1.5](https://github.com/diffo-dev/ash_neo4j/compare/v0.1.4...v0.1.5) (2025-05-31)

### Features:
* logger
* upsert nodes
* optional label

## [v0.1.4](https://github.com/diffo-dev/ash_neo4j/compare/v0.1.3...v0.1.4) (2025-05-28)

### Features:
* spark improvements

## [v0.1.3](https://github.com/diffo-dev/ash_neo4j/compare/v0.1.2...v0.1.3) (2025-05-24)

### Features:
* sort, offset, limit

## [v0.1.2](https://github.com/diffo-dev/ash_neo4j/compare/v0.1.1...v0.1.2) (2025-05-23)

### Features:
* property types, duration, relate, destroy

## [v0.1.1](https://github.com/diffo-dev/ash_neo4j/compare/v0.1.0...v0.1.1) (2025-05-05)

### Features:
* create

### Bug Fixes:
* read arbitrary resource

## [v0.1.0](https://github.com/diffo-dev/ash_neo4j/compare/v0.1.0...v0.1.0) (2025-04-30)

### Features:
* initial version, read only














