<!--
SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# Hybrid tensor + heterogeneous-compute data layer (design)

**Status:** Draft / RFC — for discussion, not yet sliced into tickets.

## Vision

Evolve ash_neo4j from a graph storage/CRUD data layer into a **knowledge substrate that stores in Neo4j and routes each operation to the engine best suited to it** — Cypher, in-memory Elixir, Nx/EXLA, or an external solver — all below the Ash line.

Consumers **model the domain whole**: rich typed attributes on the resource that means them. The data layer owns representation and compute placement. There is no shredding of a cohesive entity into satellite resources to suit the engine (the SQL antipattern), and the consumer never has to know whether `matrix_mul` ran as a graph traversal or on a GPU.

## Substrate: rank-generic typed tensors

- A **rank-generic tensor** type (1D and 2D the priority cases, N-D general), parameterised by **shape** and **element type** (`u8`, `int`, `float`, `complex`). `AshNeo4j.Types.Vector` (1D float, #74) becomes the rank-1 instance — not a special feature.
- **Structural ops are substrate-owned and value-blind.** `transpose` (kept lazy via stride/transpose metadata — O(1); materialise only when an op forces layout), `reshape`, `slice`, `gather`, `concat`, `stack`. They rearrange cells without interpreting them, so they work identically on any tensor; `slice` 2D→1D and `stack` 1D→2D bridge the ranks.
- **Semantic ops are registered** — they combine values, so they need the element algebra (see *Compute* and *DSL*).

## Storage model

Neo4j property values are primitives or homogeneous primitive arrays — there is no nested list — so storage follows a recursive rule:

- **The last axis becomes a `LIST` property; every outer axis becomes an indexed node grid.**
  - 1D = a node + `LIST`
  - 2D = a row of nodes, each a `LIST`
  - 3D = a 2D grid of nodes, each a `LIST`
  - rank R = an (R−1)-D node grid of `LIST` fibres
  - every node is a rank-1 fibre at an outer multi-index (carrying its `(i, j, …)` coordinates for ordering).

- **Representations per profile** (the data layer picks a default; `store:` overrides — see DSL):
  - **flat `LIST` + shape, or base64 blob** — a compact, opaque *operand* (loaded whole, computed elsewhere, never queried per element);
  - **node grid** — fibres are addressable and relatable; the numeric/bulk default, and the form that marshals cleanly to Nx;
  - **cell-per-node subgraph** (see #307) — fully relational; the form the reasoning cases want.

- **Two storage codecs**, chosen by **consumer × element size**:
  - native `LIST<int|float>` — for values Cypher must see (reduce/filter/relate) and for word-sized elements (a native `FLOAT` is 8 bytes, beating base64);
  - **base64 `STRING`** — for opaque, engine-only operands and sub-word elements (a `u8` value is ~1.33 bytes base64 vs an 8-byte `LIST<INTEGER>` entry).

  base64 is the established binary path (`Ash.Type.Binary`), and it is a **swappable adapter**: a binary-native store drops it with no change above, because the engine boundary is already raw binary.

## Compute: a per-op router over heterogeneous engines

This generalises the Cypher-vs-Elixir routing the data layer already does (pushdown plus in-memory refinement), adding two engines.

| Engine | Handles |
|---|---|
| **Cypher** | graph-native: traversal, reductions, sparse/semiring matmul, resolution fan-in (operand gather), constraint validation |
| **Elixir** | glue, exact in-memory refinement, small ops |
| **Nx / EXLA** | dense numeric and complex linear algebra — RF (beamforming, SVD/eigh, FFT), bulk embedding similarity |
| **logic engine** | constraint search / `solve` (CSP/SAT) |

- **Placement** is by `op × element-type × shape/density`, decided at the engine boundary by **transfer cost vs compute saving** (data gravity): reductions and elementwise stay in Cypher; dense/heavy numeric transfers out.
- **The engine contract is binary operands** (plus shape/type/driver metadata) in and out — the *universal* marshalling format. Nx tensors are binary buffers; an IEEE 1164 std_logic engine is a binary callback; a future NIF takes binary. **The contract firms up only once a second engine sits behind it** — it should not be over-designed before then.
- **Dependency boundaries are opt-in.** Heavy engines are add-on packages (`ash_neo4j_nx`, `ash_neo4j_logic`) lit up only when registered; the core stays lean.
- **Placement is inspectable.** An `explain`-style "where will this run." Hide the mechanism, not the cost.

## DSL and ownership model

Governing principle: **semantics live with the *type*; the resource just uses it; ash_neo4j introspects and composes. Conventional storage needs no declaration — only novelty does, declared where it is owned.**

Storage and dispatch are **distinct concerns** — mechanism (how it is stored) versus policy (what its ops mean) — but they describe the **same field**, so they are **co-located in one per-field declaration with distinct keys**: cohesive to read, without conflating the two.

```elixir
# On the type (TypedStruct / embedded resource `neo4j do`, or an Ash.Type contract):
neo4j do
  field :state,   resolve: AshNeo4j.Ieee1164               # conventional storage; dispatch declared
  field :grid,    store: :subgraph, solve: AshNeo4j.Logic   # novel storage + dispatch
  field :weights, store: :packed                            # storage only
end
```

- `store:` — representation (mechanism). Omit for conventional storage (the layer picks by element-size × consumer × rank).
- `resolve:` / `solve:` / `compute:` — dispatch to a registered engine (policy). Omit if the type has no semantic op.
- Omit the field entry entirely when everything is conventional.

The keys keep mechanism and policy distinguishable — the data layer still never learns *what* the values mean, only that `resolve` → module X — so co-locating does not reconflate "neo4j shouldn't know it's a Sudoku."

Where it lives:

- **Embedded resources and TypedStructs** → their own `neo4j do`, via a standalone Spark extension. **No Ash change is required** — TypedStruct DSL introspection already exists upstream (precedent: `ash_jason`, `ash_outstanding`).
- **Scalar `Ash.Type` modules** (a `StdLogic` type, the tensor types) → a type-module contract (callback) exposing the same per-field/element declaration alongside `storage_type/1`.

The **resource `neo4j do`** then reduces to graph shape (`label` / `relate` / `guard` / `skip`) plus the rare per-attribute override, in the same vocabulary — `attribute :embedding, store: :subgraph`. ash_neo4j walks the attribute/field type tree, composes a single **storage + dispatch plan baked at compile time** (a persister, as `PersistMapping` already bakes labels/translations), and **never does a type's work — it introspects.**

So `attribute :state, StdLogic` gets storage *and* resolution for free: the `StdLogic` type owns its declaration; the resource just uses the type.

## The recurring seam

Several use cases share one shape: **a graph query assembles operands → an engine solves → results write back to the graph.**

- **RF optimisation** — topology + 3D geometry (#270) selects antennas and channel matrices → Nx solves beamforming → write weights/SINR back.
- **Bulk embeddings** — a query stacks per-node embeddings into a 2D corpus → Nx batch-similarity/clustering → write neighbours/scores back. A third similarity regime beside per-row Cypher (#74) and the HNSW `queryNodes` index (#297).
- **std_logic resolution** — Cypher gathers the driver fibres (the fan-in is graph-native) → a binary callback to a single authoritative IEEE 1164 engine (verified against the reference matrix) → store the resolved binary.

## Public demonstrations

These prove the substrate spans numeric, symbolic, and constraint regimes:

- **Embeddings** — 1D float; subsumes `Vector`; bulk similarity via Nx.
- **Numeric / RF** — complex tensors; dense linear algebra in Nx/EXLA.
- **IEEE 1164 std_logic emulation** — `resolve_std_logic` via the binary callback; the subtype worlds (`bit`/`X01`/`X01Z`/`UX01`/`UX01Z`/`std_logic`) and the `to_*` conversions as projections.
- **Sudoku** — `valid_sudoku` (Cypher), `solve_sudoku` (a logic-engine action) — a graph data layer *reasoning*, not just retrieving.

## Relationships

- #74 — vector embeddings (the rank-1 seed).
- #297 — indexed KNN (`queryNodes`); a similarity regime beside bulk-Nx.
- #270 — WGS-84-3D geometry; feeds RF operand selection.
- #307 — exploded topology / Graph B-Rep; the cell-per-node subgraph representation.
- #306 — geospatial benchmarks; the harness this kind of work needs.

## Staging (decision-gated)

1. **Rank-generic tensor type + structural ops + storage model** (`LIST` / base64 / node-grid), **top-level resource attributes only**. Subsumes `Vector`. *(First slice.)*
2. Engine behaviour + dispatch, with **one** engine (Cypher-builtin) — prove the seam.
3. **Second** engine (Nx) — let the binary contract firm up; bulk embeddings as the driver.
4. IEEE 1164 binary callback (`resolve_std_logic`); logic engine + `solve` (Sudoku).
5. **TypedStruct / embedded nesting** — standalone `neo4j` section, recursive introspection and compose. Additive; **no Ash change required**; deferred from the first slice as a scope choice only.
6. 2D / N-D subgraph representation where it pays (overlaps #307).

## Cautions

- This is an evolution of ash_neo4j's existing routing, not a rewrite; storage stays Neo4j.
- A kernel orchestrating engines risks becoming a god-object — keep the engine behaviour minimal, the core thin, defaults type-driven, and the DSL for declared exceptions.
- `:subgraph` opts into a lifecycle cost (cascade on update/delete; the staleness discipline of #283/#287) — hidden but real; the default avoids it.
- Do not oversell: for pure dense numeric the graph is *storage + context*; the hybrid pays where a workload *mixes* relational selection and heavy compute.
