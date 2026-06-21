# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

# Clause structs — defined first so Cypher.Query can reference them.

defmodule AshNeo4j.Cypher.Match do
  @moduledoc "MATCH clause. `pattern` is a Cypher pattern string, e.g. `\"(s:Actor)\"`."
  @type t :: %__MODULE__{pattern: String.t()}
  defstruct [:pattern]
end

defmodule AshNeo4j.Cypher.OptionalMatch do
  @moduledoc "OPTIONAL MATCH clause."
  @type t :: %__MODULE__{pattern: String.t()}
  defstruct [:pattern]
end

defmodule AshNeo4j.Cypher.Create do
  @moduledoc "CREATE clause. `pattern` is a Cypher pattern string, e.g. `\"(n:Actor {name: $n_name})\"`."
  @type t :: %__MODULE__{pattern: String.t()}
  defstruct [:pattern]
end

defmodule AshNeo4j.Cypher.Merge do
  @moduledoc "MERGE clause. `pattern` is a Cypher pattern string."
  @type t :: %__MODULE__{pattern: String.t()}
  defstruct [:pattern]
end

defmodule AshNeo4j.Cypher.Where do
  @moduledoc "WHERE clause. Each entry in `conditions` is ANDed together."
  @type t :: %__MODULE__{conditions: [String.t()]}
  defstruct conditions: []
end

defmodule AshNeo4j.Cypher.With do
  @moduledoc "WITH clause."
  @type t :: %__MODULE__{items: [String.t()]}
  defstruct items: []
end

defmodule AshNeo4j.Cypher.Set do
  @moduledoc "SET clause. `expression` is the full SET expression, e.g. `\"n += {born: $n_born}\"`."
  @type t :: %__MODULE__{expression: String.t()}
  defstruct [:expression]
end

defmodule AshNeo4j.Cypher.OnCreateSet do
  @moduledoc "ON CREATE SET clause (MERGE). `expression` is the full SET expression, e.g. `\"n += {born: $nc_born}\"`."
  @type t :: %__MODULE__{expression: String.t()}
  defstruct [:expression]
end

defmodule AshNeo4j.Cypher.OnMatchSet do
  @moduledoc "ON MATCH SET clause (MERGE). `expression` is the full SET expression, e.g. `\"n += {touched: $nm_touched}\"`."
  @type t :: %__MODULE__{expression: String.t()}
  defstruct [:expression]
end

defmodule AshNeo4j.Cypher.Remove do
  @moduledoc "REMOVE clause. `items` is a list of property references, e.g. `[\"n.born\"]`."
  @type t :: %__MODULE__{items: [String.t()]}
  defstruct items: []
end

defmodule AshNeo4j.Cypher.Delete do
  @moduledoc "DELETE clause. `items` is a list of variables to delete, e.g. `[\"r\"]`."
  @type t :: %__MODULE__{items: [String.t()]}
  defstruct items: []
end

defmodule AshNeo4j.Cypher.DetachDelete do
  @moduledoc "DETACH DELETE clause."
  @type t :: %__MODULE__{items: [String.t()]}
  defstruct items: []
end

defmodule AshNeo4j.Cypher.Return do
  @moduledoc "RETURN clause."
  @type t :: %__MODULE__{items: [String.t()]}
  defstruct items: []
end

defmodule AshNeo4j.Cypher.OrderBy do
  @moduledoc "ORDER BY clause. Each term is a `{property_expression, :asc | :desc}` pair."
  @type sort_term :: {String.t(), :asc | :desc}
  @type t :: %__MODULE__{terms: [sort_term()]}
  defstruct terms: []
end

defmodule AshNeo4j.Cypher.Skip do
  @moduledoc "SKIP clause."
  @type t :: %__MODULE__{value: non_neg_integer()}
  defstruct [:value]
end

defmodule AshNeo4j.Cypher.Call do
  @moduledoc """
  `CALL { … }` block joining pre-rendered branch cyphers with `UNION` or
  `UNION ALL`. Used for native combination-query pushdown (`:union`,
  `:union_all`).

  Branches are stored as already-rendered Cypher strings — the caller is
  responsible for merging branch params into the outer `Cypher.Query.params`
  map before this clause is rendered.
  """
  @type union_type :: :union | :union_all
  @type t :: %__MODULE__{branches: [String.t()], union_type: union_type()}
  defstruct branches: [], union_type: :union_all
end

defmodule AshNeo4j.Cypher.Limit do
  @moduledoc "LIMIT clause."
  @type t :: %__MODULE__{value: pos_integer()}
  defstruct [:value]
end

defmodule AshNeo4j.Cypher.CallSubquery do
  @moduledoc """
  `CALL { … }` subquery block holding a pre-rendered inner query body, e.g. a
  scoped aggregate `CALL { WITH s MATCH (s)<path>(d) RETURN min(d.p) AS agg_v }`.
  Distinct from `Call`, which joins branches with `UNION`/`UNION ALL`.
  """
  @type t :: %__MODULE__{body: String.t()}
  defstruct [:body]
end

defmodule AshNeo4j.Cypher.Query do
  @moduledoc """
  Typed representation of a Cypher query, and builders for constructing common patterns.

  The struct holds an ordered list of typed clause structs and a params map.
  Callers build a query via the builder functions, then pass it to
  `AshNeo4j.Cypher.render/1` or `AshNeo4j.Cypher.run/1`.

  ## Clause structs

  Read: `Match`, `OptionalMatch`, `Where`, `With`, `Return`, `OrderBy`, `Skip`, `Limit`
  Write: `Create`, `Merge`, `Set`, `Remove`, `Delete`, `DetachDelete`
  """

  alias AshNeo4j.Cypher

  alias AshNeo4j.Cypher.{
    Match,
    OptionalMatch,
    Create,
    Merge,
    Where,
    With,
    Set,
    OnCreateSet,
    OnMatchSet,
    Remove,
    Delete,
    DetachDelete,
    Return,
    OrderBy,
    Skip,
    Limit,
    Call,
    CallSubquery
  }

  @type clause ::
          Match.t()
          | OptionalMatch.t()
          | Create.t()
          | Merge.t()
          | Where.t()
          | With.t()
          | Set.t()
          | OnCreateSet.t()
          | OnMatchSet.t()
          | Remove.t()
          | Delete.t()
          | DetachDelete.t()
          | Return.t()
          | OrderBy.t()
          | Skip.t()
          | Limit.t()
          | Call.t()
          | CallSubquery.t()

  @type t :: %__MODULE__{clauses: [clause()], params: map()}

  defstruct clauses: [], params: %{}

  @typedoc """
  A single property filter condition for `node_read_filtered/2`:
  `{property, operator_atom, value, case_insensitive?}`
  """
  @type condition :: {String.t(), atom(), any(), boolean()}

  # ---------------------------------------------------------------------------
  # Read builders
  # ---------------------------------------------------------------------------

  @doc """
  `MATCH (s:L1:L2) OPTIONAL MATCH (s)-[r]-(d) RETURN s, r, d`
  """
  @spec node_read(atom() | [atom()]) :: t()
  def node_read(label) do
    %__MODULE__{
      clauses: [
        %Match{pattern: Cypher.node(:s, List.wrap(label))},
        %OptionalMatch{pattern: "(s)-[r]-(d)"},
        %Return{items: ["s", "r", "d"]}
      ]
    }
  end

  @doc """
  `MATCH (s:L1:L2) WHERE <conditions> OPTIONAL MATCH (s)-[r]-(d) RETURN s, r, d`

  Returns `node_read/1` when `conditions` is empty.
  """
  @spec node_read_filtered(atom() | [atom()], [condition()], keyword()) :: t()
  def node_read_filtered(label, conditions, opts \\ [])
  def node_read_filtered(label, [], _opts), do: node_read(label)

  def node_read_filtered(label, conditions, opts) when is_list(conditions) do
    {where_string, params} = build_conditions(:s, conditions, opts)

    %__MODULE__{
      clauses: [
        %Match{pattern: Cypher.node(:s, List.wrap(label))},
        %Where{conditions: [where_string]},
        %OptionalMatch{pattern: "(s)-[r]-(d)"},
        %Return{items: ["s", "r", "d"]}
      ],
      params: params
    }
  end

  @doc """
  `MATCH (s:L1:L2) WHERE <where> OPTIONAL MATCH (s)-[r]-(d) RETURN s, r, d` with a
  pre-rendered `WHERE` string and its params — the `fragment(...)` escape hatch (#33),
  where the condition is author-supplied Cypher rather than a derived predicate.
  """
  @spec node_read_fragment(atom() | [atom()], String.t(), map()) :: t()
  def node_read_fragment(label, where, params) when is_binary(where) and is_map(params) do
    %__MODULE__{
      clauses: [
        %Match{pattern: Cypher.node(:s, List.wrap(label))},
        %Where{conditions: [where]},
        %OptionalMatch{pattern: "(s)-[r]-(d)"},
        %Return{items: ["s", "r", "d"]}
      ],
      params: params
    }
  end

  @doc """
  `MATCH (s:L1:L2) [WHERE <conditions>] RETURN s` — a single combination-query
  branch, sized to fit inside a `CALL { … }` block.

  No OPTIONAL MATCH (the outer combination query owns enrichment) and only
  the `s` column is returned (Cypher's `UNION`/`UNION ALL` requires identical
  column shapes across branches).

  Supports `param_prefix:` per branch — pass distinct prefixes for distinct
  branches so their param keys (`b0_s_name_0` vs `b1_s_name_0`) don't collide
  when merged.

  ## Examples
  ```
  iex> q = AshNeo4j.Cypher.Query.branch_node_read(:Place)
  iex> {cypher, _} = AshNeo4j.Cypher.render(q)
  iex> cypher
  "MATCH (s:Place) RETURN s"

  iex> q = AshNeo4j.Cypher.Query.branch_node_read(:Place, [{"name", :==, "Sydney", false}], param_prefix: "b0_")
  iex> {cypher, params} = AshNeo4j.Cypher.render(q)
  iex> cypher
  "MATCH (s:Place) WHERE s.name = $b0_s_name_0 RETURN s"
  iex> params
  %{"b0_s_name_0" => "Sydney"}
  ```
  """
  @spec branch_node_read(atom() | [atom()], [condition()], keyword()) :: t()
  def branch_node_read(label, conditions \\ [], opts \\ [])

  def branch_node_read(label, [], _opts) do
    %__MODULE__{
      clauses: [
        %Match{pattern: Cypher.node(:s, List.wrap(label))},
        %Return{items: ["s"]}
      ]
    }
  end

  def branch_node_read(label, conditions, opts) when is_list(conditions) do
    {where_string, params} = build_conditions(:s, conditions, opts)

    %__MODULE__{
      clauses: [
        %Match{pattern: Cypher.node(:s, List.wrap(label))},
        %Where{conditions: [where_string]},
        %Return{items: ["s"]}
      ],
      params: params
    }
  end

  @doc """
  Same as `branch_node_read/3` but returns just the Neo4j internal id of `s`
  (as `sid`) instead of the node itself. Used to cheaply materialise the id
  set per branch in the in-memory orchestration path for INTERSECT / EXCEPT
  combination queries.

  ## Examples
  ```
  iex> q = AshNeo4j.Cypher.Query.branch_node_read_ids(:Place, [{"name", :==, "Sydney", false}], param_prefix: "b0_")
  iex> {cypher, _} = AshNeo4j.Cypher.render(q)
  iex> cypher
  "MATCH (s:Place) WHERE s.name = $b0_s_name_0 RETURN id(s) AS sid"
  ```
  """
  @spec branch_node_read_ids(atom() | [atom()], [condition()], keyword()) :: t()
  def branch_node_read_ids(label, conditions \\ [], opts \\ [])

  def branch_node_read_ids(label, [], _opts) do
    %__MODULE__{
      clauses: [
        %Match{pattern: Cypher.node(:s, List.wrap(label))},
        %Return{items: ["id(s) AS sid"]}
      ]
    }
  end

  def branch_node_read_ids(label, conditions, opts) when is_list(conditions) do
    {where_string, params} = build_conditions(:s, conditions, opts)

    %__MODULE__{
      clauses: [
        %Match{pattern: Cypher.node(:s, List.wrap(label))},
        %Where{conditions: [where_string]},
        %Return{items: ["id(s) AS sid"]}
      ],
      params: params
    }
  end

  @doc """
  `MATCH (s:L1:L2) WHERE id(s) IN $ids OPTIONAL MATCH (s)-[r]-(d) RETURN s, r, d`.

  Used as the final read after in-memory combination orchestration computes
  the keep-set of node ids.
  """
  @spec node_read_by_ids(atom() | [atom()], [integer()]) :: t()
  def node_read_by_ids(label, ids) when is_list(ids) do
    %__MODULE__{
      clauses: [
        %Match{pattern: Cypher.node(:s, List.wrap(label))},
        %Where{conditions: ["id(s) IN $ids"]},
        %OptionalMatch{pattern: "(s)-[r]-(d)"},
        %Return{items: ["s", "r", "d"]}
      ],
      params: %{"ids" => ids}
    }
  end

  @doc """
  Wraps a list of branch queries (built via `branch_node_read/3`) in a
  `CALL { … UNION/UNION ALL … }` block followed by the outer OPTIONAL MATCH
  enrichment and `RETURN s, r, d`.

  Branch params are merged into the outer query's params map. Branches are
  rendered to Cypher strings before being placed in the `Call` clause.

  Opts:
    * `:union_type` — `:union` or `:union_all` (default `:union_all`)

  ## Examples
  ```
  iex> b0 = AshNeo4j.Cypher.Query.branch_node_read(:Place, [{"name", :==, "Sydney", false}], param_prefix: "b0_")
  iex> b1 = AshNeo4j.Cypher.Query.branch_node_read(:Place, [{"name", :==, "Melbourne", false}], param_prefix: "b1_")
  iex> q = AshNeo4j.Cypher.Query.combination_block([b0, b1])
  iex> {cypher, params} = AshNeo4j.Cypher.render(q)
  iex> cypher
  "CALL { MATCH (s:Place) WHERE s.name = $b0_s_name_0 RETURN s UNION ALL MATCH (s:Place) WHERE s.name = $b1_s_name_0 RETURN s } WITH s OPTIONAL MATCH (s)-[r]-(d) RETURN s, r, d"
  iex> params
  %{"b0_s_name_0" => "Sydney", "b1_s_name_0" => "Melbourne"}
  ```
  """
  @spec combination_block([t()], keyword()) :: t()
  def combination_block(branches, opts \\ []) when is_list(branches) do
    union_type = Keyword.get(opts, :union_type, :union_all)

    {rendered_branches, merged_params} =
      Enum.reduce(branches, {[], %{}}, fn branch, {acc_cyphers, acc_params} ->
        # prefix?: false — the CYPHER 25 selector belongs only on the outer
        # query, never on a branch inside the CALL { … } block (#299).
        {cypher, branch_params} = Cypher.render(branch, prefix?: false)
        {[cypher | acc_cyphers], Map.merge(acc_params, branch_params)}
      end)

    %__MODULE__{
      clauses: [
        %Call{branches: Enum.reverse(rendered_branches), union_type: union_type},
        %With{items: ["s"]},
        %OptionalMatch{pattern: "(s)-[r]-(d)"},
        %Return{items: ["s", "r", "d"]}
      ],
      params: merged_params
    }
  end

  @doc """
  `MATCH (s:SrcLabels)-[r:EdgeLabel]-(d:DestLabel) WHERE d.prop <op> $param WITH s MATCH (s)-[r0]-(d0) RETURN s, r0, d0`
  """
  @spec relationship_read(atom() | [atom()], atom(), atom(), atom(), String.t(), atom(), any()) :: t()
  def relationship_read(src_label, edge_label, direction, dest_label, dest_property, operator, value)
      when is_atom(edge_label) and is_atom(direction) and is_atom(dest_label) do
    param_key = "d_#{dest_property}"

    match_pattern =
      Cypher.node(:s, List.wrap(src_label)) <>
        Cypher.relationship(:r, edge_label, direction) <>
        Cypher.node(:d, [dest_label])

    where_condition = Cypher.expression(:d, dest_property, convert_operator(operator), "$#{param_key}")

    %__MODULE__{
      clauses: [
        %Match{pattern: match_pattern},
        %Where{conditions: [where_condition]},
        %With{items: ["s"]},
        %Match{pattern: "(s)-[r0]-(d0)"},
        %Return{items: ["s", "r0", "d0"]}
      ],
      params: %{param_key => value}
    }
  end

  @doc """
  Multi-hop traversal filter (#321) — generalises `relationship_read/7` to a path.

  `MATCH (s:Src)<path>(d) WHERE <reached conditions> WITH DISTINCT s MATCH (s)-[r0]-(d0) RETURN s, r0, d0`

  `path_segments` is `[{edge_label, direction, dest_label}]` (dest_label may be
  `nil` for an unlabelled hop); the reached node binds as `d`. `conditions` are
  the same `{prop, op, val, ci?}` tuples the property/spatial/vector path uses —
  rendered against `d` via `build_conditions/3`, so a reached-node field
  comparison, `st_dwithin`, `st_distance` or vector predicate all compose here.
  `WITH DISTINCT s` collapses a source matched via multiple paths to one row.
  """
  @spec traversal_read(atom() | [atom()], [{atom(), atom(), atom() | nil}], [tuple()]) :: t()
  def traversal_read(src_label, path_segments, conditions)
      when is_list(path_segments) and path_segments != [] and is_list(conditions) do
    {where_string, params} = build_conditions(:d, conditions, [])
    match_pattern = Cypher.node(:s, List.wrap(src_label)) <> build_agg_path(path_segments)

    %__MODULE__{
      clauses: [
        %Match{pattern: match_pattern},
        %Where{conditions: [where_string]},
        %With{items: ["DISTINCT s"]},
        %Match{pattern: "(s)-[r0]-(d0)"},
        %Return{items: ["s", "r0", "d0"]}
      ],
      params: params
    }
  end

  @doc """
  Existence / cardinality of a traversal's reached set (#334) — a `WHERE`
  predicate on the source, not a field comparison on the reached node.

  `MATCH (s:Src) WHERE EXISTS { MATCH (s)<path>(d) } OPTIONAL MATCH (s)-[r]-(d0) RETURN s, r, d0`
  `MATCH (s:Src) WHERE COUNT { MATCH (s)<path>(d) RETURN DISTINCT d } > $n OPTIONAL MATCH (s)-[r]-(d0) RETURN s, r, d0`

  `agg` selects the predicate:

    * `{:exists, true}`  → `EXISTS { … }` (short-circuits on first match)
    * `{:exists, false}` → `NOT EXISTS { … }` (membership exclusion)
    * `{:count, op, n}`  → `COUNT { … RETURN DISTINCT d } <op> $n` (distinct reached nodes)

  The source is filtered directly (no per-path row fan-out), and enrichment uses
  `OPTIONAL MATCH` so a `NOT EXISTS` source with no other edges still returns.
  Needs no reached-resource typing, so it composes over reverse chains too.
  """
  @spec traversal_predicate_read(atom() | [atom()], [{atom(), atom(), atom() | nil}], tuple()) :: t()
  def traversal_predicate_read(src_label, path_segments, agg)
      when is_list(path_segments) and path_segments != [] do
    path_pattern = "(s)" <> build_agg_path(path_segments)
    {where_string, params} = build_traversal_predicate(path_pattern, agg)

    %__MODULE__{
      clauses: [
        %Match{pattern: Cypher.node(:s, List.wrap(src_label))},
        %Where{conditions: [where_string]},
        %OptionalMatch{pattern: "(s)-[r]-(d0)"},
        %Return{items: ["s", "r", "d0"]}
      ],
      params: params
    }
  end

  defp build_traversal_predicate(path_pattern, {:exists, true}),
    do: {"EXISTS { MATCH #{path_pattern} }", %{}}

  defp build_traversal_predicate(path_pattern, {:exists, false}),
    do: {"NOT EXISTS { MATCH #{path_pattern} }", %{}}

  defp build_traversal_predicate(path_pattern, {:count, op, value}) do
    key = "traverse_count_0"
    {"COUNT { MATCH #{path_pattern} RETURN DISTINCT d } #{convert_operator(op)} $#{key}", %{key => value}}
  end

  @doc """
  Field aggregate over a traversal's reached set (#338) compared against a value.

  No native `MIN {}`/`MAX {}`/`AVG {}`/`SUM {}` subquery expression exists, so
  this uses a scoped `CALL` that aggregates the reached field, then filters the
  scalar — plain Cypher 5 (the `WITH s` import form, not `CALL (s) {}`):

  `MATCH (s:Src) CALL { WITH s MATCH (s)<path>(d) RETURN min(d.p) AS agg_v } WITH s, agg_v WHERE agg_v <op> $v OPTIONAL MATCH (s)-[r]-(d0) RETURN s, r, d0`

  `agg` is `{agg_fn, prop, op, value}` where `agg_fn ∈ [:min, :max, :avg, :sum]`
  and `prop` is the already-resolved reached-node property name.

  Empty-set semantics follow Neo4j's aggregating functions and differ by `agg_fn`:
  `min`/`max`/`avg` over a no-reach source yield `null` (so `null <op> $v` drops
  it), while `sum` yields `0` (like `count`) and can still match a comparison.
  """
  @spec traversal_aggregate_read(atom() | [atom()], [{atom(), atom(), atom() | nil}], tuple()) :: t()
  def traversal_aggregate_read(src_label, path_segments, {agg_fn, prop, op, value})
      when is_list(path_segments) and path_segments != [] and agg_fn in [:min, :max, :avg, :sum] do
    path = "(s)" <> build_agg_path(path_segments)
    key = "traverse_agg_0"
    body = "WITH s MATCH #{path} RETURN #{agg_fn}(d.#{prop}) AS agg_v"

    %__MODULE__{
      clauses: [
        %Match{pattern: Cypher.node(:s, List.wrap(src_label))},
        %CallSubquery{body: body},
        %With{items: ["s", "agg_v"]},
        %Where{conditions: ["agg_v #{convert_operator(op)} $#{key}"]},
        %OptionalMatch{pattern: "(s)-[r]-(d0)"},
        %Return{items: ["s", "r", "d0"]}
      ],
      params: %{key => value}
    }
  end

  @doc """
  `MATCH (n:L1:L2 {props}) OPTIONAL MATCH (n)-[r]-(d) RETURN n, r, d`

  Like `node_read/1` but matches by properties in the MATCH pattern (not a WHERE clause).
  """
  @spec node_read_with_properties(atom() | [atom()], map()) :: t()
  def node_read_with_properties(label, properties) when is_map(properties) do
    {pattern, params} = Cypher.parameterized_node(:s, List.wrap(label), properties)

    %__MODULE__{
      clauses: [
        %Match{pattern: pattern},
        %OptionalMatch{pattern: "(s)-[r]-(d)"},
        %Return{items: ["s", "r", "d"]}
      ],
      params: params
    }
  end

  @doc """
  `MATCH (n:Labels {props}) RETURN n`
  """
  @spec match_nodes(atom() | [atom()], map()) :: t()
  def match_nodes(labels, properties \\ %{}) when is_map(properties) do
    {pattern, params} = Cypher.parameterized_node(:n, List.wrap(labels), properties)
    %__MODULE__{clauses: [%Match{pattern: pattern}, %Return{items: ["n"]}], params: params}
  end

  @doc """
  Appends an `ORDER BY` clause. No-op when `terms` is empty.

  Each term is `{order_expression, :asc | :desc}` where `order_expression` is a
  fully-formed Cypher expression — e.g. `"s.name"` for a plain property or
  `"vector.similarity.cosine(s.embedding, $q)"` for an expression sort. The
  caller (`AshNeo4j.QueryHelper`'s sort handling) is responsible for the `s.`
  prefix and for merging any referenced params via `merge_params/2`.
  """
  @spec add_order_by(t(), [{String.t(), :asc | :desc}]) :: t()
  def add_order_by(%__MODULE__{} = query, []), do: query

  def add_order_by(%__MODULE__{} = query, terms) when is_list(terms) do
    %{query | clauses: query.clauses ++ [%OrderBy{terms: terms}]}
  end

  @doc "Merges `params` into the query's param map. Later keys win."
  @spec merge_params(t(), map()) :: t()
  def merge_params(%__MODULE__{} = query, params) when is_map(params) do
    %{query | params: Map.merge(query.params, params)}
  end

  @doc "Appends a `SKIP` clause. No-op when `n` is `nil` or `0`."
  @spec add_skip(t(), non_neg_integer() | nil) :: t()
  def add_skip(%__MODULE__{} = query, n) when n in [nil, 0], do: query
  def add_skip(%__MODULE__{} = query, n), do: %{query | clauses: query.clauses ++ [%Skip{value: n}]}

  @doc "Appends a `LIMIT` clause. No-op when `n` is `nil`."
  @spec add_limit(t(), pos_integer() | nil) :: t()
  def add_limit(%__MODULE__{} = query, nil), do: query
  def add_limit(%__MODULE__{} = query, n), do: %{query | clauses: query.clauses ++ [%Limit{value: n}]}

  @doc """
  Applies `SKIP`/`LIMIT` pagination (and the `ORDER BY` that makes them
  deterministic) to the distinct source nodes `s`, **before** the edge-expansion
  step of a node read.

  The node-read shapes (`node_read/1`, `node_read_filtered/3`, `node_read_by_ids/2`,
  `relationship_read/7`, and the combination final read) all expand one row per
  edge via the clause immediately preceding the `RETURN`
  (`OPTIONAL MATCH (s)-[r]-(d)` etc.). A trailing `SKIP`/`LIMIT` would therefore
  truncate *edges*, not *nodes* — dropping relationships (e.g. a `belongs_to`
  edge) from nodes that have more edges than the limit. This inserts
  `WITH s [ORDER BY …] [SKIP …] [LIMIT …]` ahead of that expansion so pagination
  is scoped to nodes.

  No-op when there is no `skip` and no `limit` (a sort alone is handled by the
  trailing `add_order_by/2`, which orders the per-edge rows by node property and
  so keeps each node's rows grouped).
  """
  @spec paginate_nodes(t(), [{String.t(), :asc | :desc}], non_neg_integer() | nil, pos_integer() | nil) :: t()
  def paginate_nodes(%__MODULE__{} = query, order_terms, skip, limit) do
    order_terms = order_terms || []

    if skip in [nil, 0] and is_nil(limit) do
      query
    else
      page = pagination_subclauses(order_terms, skip, limit)
      return_idx = Enum.find_index(query.clauses, &match?(%Return{}, &1))
      {before, rest} = Enum.split(query.clauses, return_idx - 1)

      new_before =
        case List.last(before) do
          %With{} -> before ++ page
          _ -> before ++ [%With{items: ["s"]} | page]
        end

      %{query | clauses: new_before ++ rest}
    end
  end

  defp pagination_subclauses(order_terms, skip, limit) do
    order =
      case order_terms do
        [] -> []
        terms -> [%OrderBy{terms: terms}]
      end

    skip_clause = if skip in [nil, 0], do: [], else: [%Skip{value: skip}]
    limit_clause = if is_nil(limit), do: [], else: [%Limit{value: limit}]

    order ++ skip_clause ++ limit_clause
  end

  # ---------------------------------------------------------------------------
  # Aggregate builders
  # ---------------------------------------------------------------------------

  @doc """
  Related-nodes query — returns one row per (source, destination) pair for expression-based
  aggregates that need full destination records for Elixir-side evaluation.

  `MATCH (s:L1:L2) WHERE s.pk IN $agg_ids OPTIONAL MATCH (s)<path>(d) RETURN s.pk AS source_id, d AS dest_node`
  """
  @spec related_nodes(atom() | [atom()], atom(), [any()], [{atom(), atom(), atom()}]) :: t()
  def related_nodes(source_label, pk_field, ids, path_segments)
      when is_atom(pk_field) and is_list(ids) and is_list(path_segments) do
    path = build_agg_path(path_segments)
    src = labels_string(source_label)

    %__MODULE__{
      clauses: [
        %Match{pattern: "(s:#{src})"},
        %Where{conditions: ["s.#{pk_field} IN $agg_ids"]},
        %OptionalMatch{pattern: "(s)#{path}"},
        %Return{items: ["s.#{pk_field} AS source_id", "d AS dest_node"]}
      ],
      params: %{"agg_ids" => ids}
    }
  end

  @doc """
  Per-record aggregate — returns one row per source node with the aggregate value.

  `MATCH (s:L1:L2) WHERE s.pk IN $agg_ids OPTIONAL MATCH (s)<path>(d) RETURN s.pk AS source_id, agg_fn AS name`

  `path_segments` is a list of `{edge_label, direction, dest_label}` tuples describing
  the traversal from source to the node being aggregated.
  """
  @spec aggregate_per_record(
          atom() | [atom()],
          atom(),
          [any()],
          [{atom(), atom(), atom()}],
          atom(),
          atom() | nil,
          atom(),
          boolean(),
          [{String.t(), any()}]
        ) :: t()
  def aggregate_per_record(
        source_label,
        pk_field,
        ids,
        path_segments,
        kind,
        field,
        name,
        uniq? \\ false,
        dest_conditions \\ []
      )
      when is_atom(pk_field) and is_list(ids) and is_list(path_segments) and is_atom(kind) do
    path = build_agg_path(path_segments)
    expr = aggregate_expr(kind, field, name, uniq?)
    src = labels_string(source_label)
    {dest_where, dest_params} = build_dest_conditions(dest_conditions)

    %__MODULE__{
      clauses:
        [
          %Match{pattern: "(s:#{src})"},
          %Where{conditions: ["s.#{pk_field} IN $agg_ids"]},
          %OptionalMatch{pattern: "(s)#{path}"}
        ] ++ dest_where ++ [%Return{items: ["s.#{pk_field} AS source_id", expr]}],
      params: Map.merge(%{"agg_ids" => ids}, dest_params)
    }
  end

  @doc """
  Total aggregate — returns a single row with the aggregate value across all source nodes.

  `MATCH (s:L1:L2) WHERE s.pk IN $agg_ids OPTIONAL MATCH (s)<path>(d) RETURN agg_fn AS name`
  """
  @spec aggregate_total(
          atom() | [atom()],
          atom(),
          [any()],
          [{atom(), atom(), atom()}],
          atom(),
          atom() | nil,
          atom(),
          boolean(),
          [{String.t(), any()}]
        ) :: t()
  def aggregate_total(
        source_label,
        pk_field,
        ids,
        path_segments,
        kind,
        field,
        name,
        uniq? \\ false,
        dest_conditions \\ []
      )
      when is_atom(pk_field) and is_list(ids) and is_list(path_segments) and is_atom(kind) do
    src = labels_string(source_label)

    case path_segments do
      [] ->
        # Root-node aggregate (no relationship path, #291) — aggregate over the
        # source node `s` directly; there is no `d` to bind, so no OPTIONAL MATCH.
        %__MODULE__{
          clauses: [
            %Match{pattern: "(s:#{src})"},
            %Where{conditions: ["s.#{pk_field} IN $agg_ids"]},
            %Return{items: [aggregate_expr(kind, field, name, uniq?, "s")]}
          ],
          params: %{"agg_ids" => ids}
        }

      _ ->
        path = build_agg_path(path_segments)
        expr = aggregate_expr(kind, field, name, uniq?)
        {dest_where, dest_params} = build_dest_conditions(dest_conditions)

        %__MODULE__{
          clauses:
            [
              %Match{pattern: "(s:#{src})"},
              %Where{conditions: ["s.#{pk_field} IN $agg_ids"]},
              %OptionalMatch{pattern: "(s)#{path}"}
            ] ++ dest_where ++ [%Return{items: [expr]}],
          params: Map.merge(%{"agg_ids" => ids}, dest_params)
        }
    end
  end

  # ---------------------------------------------------------------------------
  # Write builders
  # ---------------------------------------------------------------------------

  @doc """
  `CREATE (n:L1:L2 {props}) RETURN n`
  """
  @spec create_node(atom() | [atom()], map()) :: t()
  def create_node(labels, properties) when is_map(properties) do
    {pattern, params} = Cypher.parameterized_node(:n, List.wrap(labels), properties)
    %__MODULE__{clauses: [%Create{pattern: pattern}, %Return{items: ["n"]}], params: params}
  end

  @doc """
  `MERGE (n:Label {props}) RETURN n`
  """
  @spec merge_node(atom(), map()) :: t()
  def merge_node(label, properties) when is_atom(label) and is_map(properties) do
    {pattern, params} = Cypher.parameterized_node(:n, [label], properties)
    %__MODULE__{clauses: [%Merge{pattern: pattern}, %Return{items: ["n"]}], params: params}
  end

  @doc """
  Atomic upsert (#379): `MERGE (n:L1:L2 {merge_props}) [ON CREATE SET n += {create_props}]
  [ON MATCH SET n += {match_props}] RETURN n`.

  `merge_props` are the upsert identity's properties (matched-or-created on);
  `create_props` are the rest of the node, set only when a new node is created;
  `match_props` are the `set_on_upsert` fields, set only when an existing node is
  matched. With the identity's uniqueness constraint (#20) this is a race-free,
  single-statement upsert. Param prefixes are distinct (`n_`/`nc_`/`nm_`) so the
  three property sets on the `:n` alias don't collide.
  """
  @spec upsert_node(atom() | [atom()], map(), map(), map()) :: t()
  def upsert_node(label, merge_props, create_props, match_props)
      when is_map(merge_props) and is_map(create_props) and is_map(match_props) do
    {merge_pattern, merge_params} = Cypher.parameterized_node(:n, List.wrap(label), merge_props)
    {create_cypher, create_params} = Cypher.parameterized_properties(:nc, create_props)
    {match_cypher, match_params} = Cypher.parameterized_properties(:nm, match_props)

    on_create = if map_size(create_props) > 0, do: [%OnCreateSet{expression: "n += #{create_cypher}"}], else: []
    on_match = if map_size(match_props) > 0, do: [%OnMatchSet{expression: "n += #{match_cypher}"}], else: []

    %__MODULE__{
      clauses: [%Merge{pattern: merge_pattern}] ++ on_create ++ on_match ++ [%Return{items: ["n"]}],
      params: merge_params |> Map.merge(create_params) |> Map.merge(match_params)
    }
  end

  @doc """
  `MATCH (n:L1:L2 {match_props}) [WHERE guard] SET n += {set_props} [, n.x = <expr>]
  REMOVE n.p1, n.p2 RETURN n`

  Handles all combinations of empty/non-empty set_props and remove_props. `opts`:

    * `:guard` — `changeset.filter` conditions (#361); rendered as a `WHERE`
      between the `MATCH` and `SET`. Zero matched rows ⇒ the caller raises
      `StaleRecord`.
    * `:atomics` — `{set_expressions, params}` for `changeset.atomics` (#361):
      live-node `SET n.<prop> = <expr>` clauses (already rendered against `:n`).
  """
  @spec update_node(atom() | [atom()], map(), map(), [atom()], keyword()) :: t()
  def update_node(label, match_props, set_props, remove_props \\ [], opts \\ [])
      when is_map(match_props) and is_map(set_props) and is_list(remove_props) and is_list(opts) do
    {match_pattern, match_params} = Cypher.parameterized_node(:n, List.wrap(label), match_props)
    {props_cypher, set_params} = Cypher.parameterized_properties(:n, set_props)
    {guard_clauses, guard_params} = guard_where(Keyword.get(opts, :guard, []))
    {atomic_exprs, atomic_params} = Keyword.get(opts, :atomics, {[], %{}})

    set_exprs =
      (if(map_size(set_props) > 0, do: ["n += #{props_cypher}"], else: [])) ++ atomic_exprs

    set_clauses = if set_exprs != [], do: [%Set{expression: Enum.join(set_exprs, ", ")}], else: []

    remove_clauses =
      if remove_props != [],
        do: [%Remove{items: Enum.map(remove_props, &"n.#{Cypher.quote_if_dotted(&1)}")}],
        else: []

    %__MODULE__{
      clauses:
        [%Match{pattern: match_pattern}] ++
          guard_clauses ++ set_clauses ++ remove_clauses ++ [%Return{items: ["n"]}],
      params: match_params |> Map.merge(set_params) |> Map.merge(guard_params) |> Map.merge(atomic_params)
    }
  end

  # The `changeset.filter` guard (#361) as a `WHERE` between the `MATCH` and `SET`.
  # Rendered against the `:n` update alias; params are `g_`-prefixed so they can't
  # collide with the match/set params on the same alias.
  defp guard_where([]), do: {[], %{}}

  defp guard_where(conditions) do
    {where_string, params} = build_conditions(:n, conditions, param_prefix: "g_")
    {[%Where{conditions: [where_string]}], params}
  end

  @doc """
  `MATCH (n:L1:L2 {match_props}) SET n:Add1:Add2 REMOVE n:Rem1:Rem2 RETURN n`

  Adds and/or removes node labels on a matched node. A node's label set drives
  `AshNeo4j.worlds/1`, so this moves a node between worlds — handy in tests to
  place a node in (or strip it of) a resolvable world after an Ash create.
  Handles all combinations of empty/non-empty add and remove lists.
  """
  @spec update_node_labels(atom() | [atom()], map(), [atom()], [atom()]) :: t()
  def update_node_labels(label, match_props, add_labels, remove_labels \\ [])
      when is_map(match_props) and is_list(add_labels) and is_list(remove_labels) do
    {match_pattern, params} = Cypher.parameterized_node(:n, List.wrap(label), match_props)

    set_clauses =
      if add_labels != [], do: [%Set{expression: "n:" <> Enum.map_join(add_labels, ":", &to_string/1)}], else: []

    remove_clauses =
      if remove_labels != [], do: [%Remove{items: ["n:" <> Enum.map_join(remove_labels, ":", &to_string/1)]}], else: []

    %__MODULE__{
      clauses: [%Match{pattern: match_pattern}] ++ set_clauses ++ remove_clauses ++ [%Return{items: ["n"]}],
      params: params
    }
  end

  @doc """
  `MATCH (n:L1:L2 {props}) DETACH DELETE n`
  """
  @spec delete_nodes(atom() | [atom()], map()) :: t()
  def delete_nodes(label, properties \\ %{}) when is_map(properties) do
    {pattern, params} = Cypher.parameterized_node(:n, List.wrap(label), properties)
    %__MODULE__{clauses: [%Match{pattern: pattern}, %DetachDelete{items: ["n"]}], params: params}
  end

  @doc """
  `MATCH (n:L1:L2 {props}) WHERE NOT guard1 AND NOT guard2 DETACH DELETE n`

  `guards` is a list of `{edge_label, direction, dest_label}` tuples.
  Falls back to `delete_nodes/2` when guards is empty.
  """
  @spec delete_nodes_guarded(atom() | [atom()], map(), list()) :: t()
  def delete_nodes_guarded(label, properties, []), do: delete_nodes(label, properties)

  def delete_nodes_guarded(label, properties, guards)
      when is_map(properties) and is_list(guards) do
    {pattern, params} = Cypher.parameterized_node(:n, List.wrap(label), properties)

    conditions =
      Enum.map(guards, fn {edge_label, direction, dest_label} ->
        guard_condition(:n, edge_label, direction, dest_label)
      end)

    %__MODULE__{
      clauses: [%Match{pattern: pattern}, %Where{conditions: conditions}, %DetachDelete{items: ["n"]}],
      params: params
    }
  end

  @doc """
  Single guarded + filtered destroy (#361): `MATCH (n:L {id}) WHERE <filter> AND NOT
  <guard…> DETACH DELETE n`. The `changeset.filter` optimistic-lock conditions are
  ANDed with the preservation guards. Run via `run_expecting_deletions/1`: zero
  deletions ⇒ the caller disambiguates filter-miss (StaleRecord) from guard
  (Unavailable) with `node_matching/3`.
  """
  @spec delete_node_filtered(atom() | [atom()], map(), list(), list()) :: t()
  def delete_node_filtered(label, id_props, filter_conditions, guards)
      when is_map(id_props) and is_list(filter_conditions) and is_list(guards) do
    {pattern, id_params} = Cypher.parameterized_node(:n, List.wrap(label), id_props)
    {filter_where, filter_params} = build_conditions(:n, filter_conditions, param_prefix: "f_")

    guard_conditions =
      Enum.map(guards, fn {edge_label, direction, dest_label} ->
        guard_condition(:n, edge_label, direction, dest_label)
      end)

    where_items = if(filter_where == "", do: [], else: [filter_where]) ++ guard_conditions

    %__MODULE__{
      clauses: [%Match{pattern: pattern}, %Where{conditions: where_items}, %DetachDelete{items: ["n"]}],
      params: Map.merge(id_params, filter_params)
    }
  end

  @doc """
  `MATCH (n:L {id}) WHERE <filter> RETURN n` — the optimistic-lock existence check
  (no guard) used to disambiguate a zero-deletion `delete_node_filtered/4` (#361).
  """
  @spec node_matching(atom() | [atom()], map(), list()) :: t()
  def node_matching(label, id_props, filter_conditions)
      when is_map(id_props) and is_list(filter_conditions) do
    {pattern, id_params} = Cypher.parameterized_node(:n, List.wrap(label), id_props)
    {filter_where, filter_params} = build_conditions(:n, filter_conditions, param_prefix: "f_")
    where_clauses = if filter_where == "", do: [], else: [%Where{conditions: [filter_where]}]

    %__MODULE__{
      clauses: [%Match{pattern: pattern}] ++ where_clauses ++ [%Return{items: ["n"]}],
      params: Map.merge(id_params, filter_params)
    }
  end

  @doc """
  Bulk destroy (#361): `MATCH (n:L) WHERE <filter> AND NOT <guard…> DETACH DELETE n`.
  Deletes every node matching `conditions` (the pushed-down query filter) that
  isn't protected by a preservation `guard` — guarded nodes are skipped, not
  errored ("delete what is safe"). When `return?`, the node's `properties`/`id`/
  `labels` are captured in a `WITH` *before* the delete (a returned deleted node
  has empty properties) and returned for record reconstruction.
  """
  @spec bulk_detach_delete(atom() | [atom()], list(), list(), boolean()) :: t()
  def bulk_detach_delete(label, conditions, guards, return?)
      when is_list(conditions) and is_list(guards) and is_boolean(return?) do
    {filter_where, params} = build_conditions(:n, conditions, param_prefix: "f_")

    guard_conditions =
      Enum.map(guards, fn {edge_label, direction, dest_label} ->
        guard_condition(:n, edge_label, direction, dest_label)
      end)

    where_items = if(filter_where == "", do: [], else: [filter_where]) ++ guard_conditions
    where_clauses = if where_items == [], do: [], else: [%Where{conditions: where_items}]

    {capture_clauses, return_clauses} =
      if return? do
        {[%With{items: ["n", "properties(n) AS props", "id(n) AS nid", "labels(n) AS labels"]}],
         [%Return{items: ["props", "nid", "labels"]}]}
      else
        {[], []}
      end

    %__MODULE__{
      clauses:
        [%Match{pattern: Cypher.node(:n, List.wrap(label))}] ++
          where_clauses ++ capture_clauses ++ [%DetachDelete{items: ["n"]}] ++ return_clauses,
      params: params
    }
  end

  @doc """
  `MATCH (s:SrcLabel {s_props}) [WHERE guard] OPTIONAL MATCH (d:DestLabel {d_props}) MERGE (s)-[r:EDGE]->(d) RETURN s, r, d`

  `opts[:guard]` is a `changeset.filter` condition list (#368) gating the attach on
  the live source node; a guard miss yields zero rows ⇒ the caller raises `StaleRecord`.
  """
  @spec relate(atom() | [atom()], map(), atom() | [atom()], map(), atom(), atom(), keyword()) :: t()
  def relate(src_label, src_props, dest_label, dest_props, edge_label, direction, opts \\ [])
      when is_atom(edge_label) and is_atom(direction) and is_list(opts) do
    {src_pattern, src_params} = Cypher.parameterized_node(:s, List.wrap(src_label), src_props)
    {dest_pattern, dest_params} = Cypher.parameterized_node(:d, List.wrap(dest_label), dest_props)
    {guard_clauses, guard_params} = source_guard_where(Keyword.get(opts, :guard, []))

    %__MODULE__{
      clauses:
        [%Match{pattern: src_pattern}] ++
          guard_clauses ++
          [
            %OptionalMatch{pattern: dest_pattern},
            %Merge{pattern: "(s)" <> Cypher.relationship(:r, edge_label, direction) <> "(d)"},
            %Return{items: ["s", "r", "d"]}
          ],
      params: src_params |> Map.merge(dest_params) |> Map.merge(guard_params)
    }
  end

  @doc """
  Relates two nodes, first removing any existing edge of the same type from the source.

      MATCH (s:SrcLabel {s_props})
      WITH s OPTIONAL MATCH (s)-[r0:EDGE]->(d0:DestLabel)
      DELETE r0 WITH s MATCH (d:DestLabel {d_props})
      MERGE (s)-[r:EDGE]->(d) RETURN s, r, d
  """
  @spec relate_unrelating_source(atom() | [atom()], map(), atom(), map(), atom(), atom(), keyword()) :: t()
  def relate_unrelating_source(src_label, src_props, dest_label, dest_props, edge_label, direction, opts \\ [])
      when is_atom(dest_label) and is_atom(edge_label) and is_atom(direction) and is_list(opts) do
    {src_pattern, src_params} = Cypher.parameterized_node(:s, List.wrap(src_label), src_props)
    {dest_pattern, dest_params} = Cypher.parameterized_node(:d, [dest_label], dest_props)
    {guard_clauses, guard_params} = source_guard_where(Keyword.get(opts, :guard, []))

    %__MODULE__{
      clauses:
        [%Match{pattern: src_pattern}] ++
          guard_clauses ++
          [
        %With{items: ["s"]},
        %OptionalMatch{
          pattern: "(s)" <> Cypher.relationship(:r0, edge_label, direction) <> Cypher.node(:d0, [dest_label])
        },
        %Delete{items: ["r0"]},
        %With{items: ["s"]},
        %Match{pattern: dest_pattern},
        %Merge{pattern: "(s)" <> Cypher.relationship(:r, edge_label, direction) <> "(d)"},
        %Return{items: ["s", "r", "d"]}
      ],
      params: src_params |> Map.merge(dest_params) |> Map.merge(guard_params)
    }
  end

  @doc """
  Relates two nodes, first removing any existing edge of the same type pointing to the destination.

      MATCH (s:SrcLabel {s_props}) OPTIONAL MATCH (d:DestLabel {d_props})
      WITH s, d OPTIONAL MATCH (s0:SrcLabel)-[r0:EDGE]->(d) WHERE s0 <> s
      DELETE r0 WITH s, d MERGE (s)-[r:EDGE]->(d) RETURN s, r, d
  """
  @spec relate_unrelating_destination(atom() | [atom()], map(), atom(), map(), atom(), atom(), keyword()) :: t()
  def relate_unrelating_destination(src_label, src_props, dest_label, dest_props, edge_label, direction, opts \\ [])
      when is_atom(dest_label) and is_atom(edge_label) and is_atom(direction) and is_list(opts) do
    src_labels = List.wrap(src_label)
    {src_pattern, src_params} = Cypher.parameterized_node(:s, src_labels, src_props)
    {dest_pattern, dest_params} = Cypher.parameterized_node(:d, [dest_label], dest_props)
    {guard_clauses, guard_params} = source_guard_where(Keyword.get(opts, :guard, []))

    %__MODULE__{
      clauses:
        [%Match{pattern: src_pattern}] ++
          guard_clauses ++
          [
        %OptionalMatch{pattern: dest_pattern},
        %With{items: ["s", "d"]},
        %OptionalMatch{
          pattern: Cypher.node(:s0, src_labels) <> Cypher.relationship(:r0, edge_label, direction) <> "(d)"
        },
        %Where{conditions: ["s0 <> s"]},
        %Delete{items: ["r0"]},
        %With{items: ["s", "d"]},
        %Merge{pattern: "(s)" <> Cypher.relationship(:r, edge_label, direction) <> "(d)"},
        %Return{items: ["s", "r", "d"]}
      ],
      params: src_params |> Map.merge(dest_params) |> Map.merge(guard_params)
    }
  end

  @doc """
  Relates two nodes, removing existing edges from source AND to destination.

      MATCH (s:SrcLabel {s_props}) WITH s
      OPTIONAL MATCH (s)-[r0:EDGE]->(d:DestLabel {d_props}) DELETE r0 WITH s
      OPTIONAL MATCH (d:DestLabel {d_props}) WITH s, d
      OPTIONAL MATCH (s0:SrcLabel)-[r0:EDGE]->(d) WHERE s0 <> s DELETE r0
      WITH s, d MERGE (s)-[r:EDGE]->(d) RETURN s, r, d
  """
  @spec relate_unrelating_both(atom() | [atom()], map(), atom(), map(), atom(), atom(), keyword()) :: t()
  def relate_unrelating_both(src_label, src_props, dest_label, dest_props, edge_label, direction, opts \\ [])
      when is_atom(dest_label) and is_atom(edge_label) and is_atom(direction) and is_list(opts) do
    src_labels = List.wrap(src_label)
    {src_pattern, src_params} = Cypher.parameterized_node(:s, src_labels, src_props)
    {dest_pattern, dest_params} = Cypher.parameterized_node(:d, [dest_label], dest_props)
    {guard_clauses, guard_params} = source_guard_where(Keyword.get(opts, :guard, []))

    %__MODULE__{
      clauses:
        [%Match{pattern: src_pattern}] ++
          guard_clauses ++
          [
        %With{items: ["s"]},
        %OptionalMatch{pattern: "(s)" <> Cypher.relationship(:r0, edge_label, direction) <> dest_pattern},
        %Delete{items: ["r0"]},
        %With{items: ["s"]},
        %OptionalMatch{pattern: dest_pattern},
        %With{items: ["s", "d"]},
        %OptionalMatch{
          pattern: Cypher.node(:s0, src_labels) <> Cypher.relationship(:r0, edge_label, direction) <> "(d)"
        },
        %Where{conditions: ["s0 <> s"]},
        %Delete{items: ["r0"]},
        %With{items: ["s", "d"]},
        %Merge{pattern: "(s)" <> Cypher.relationship(:r, edge_label, direction) <> "(d)"},
        %Return{items: ["s", "r", "d"]}
      ],
      params: src_params |> Map.merge(dest_params) |> Map.merge(guard_params)
    }
  end

  @doc """
  `MATCH (s:SrcLabel {s_props})-[r:EDGE]->(d:DestLabel {d_props}) [WHERE guard] DELETE r RETURN s, d`

  `opts[:guard]` is a `changeset.filter` condition list (#368) gating the detach on
  the live source node; a guard miss yields zero rows ⇒ the caller raises `StaleRecord`.
  """
  @spec unrelate(atom() | [atom()], map(), atom(), map(), atom(), atom(), keyword()) :: t()
  def unrelate(src_label, src_props, dest_label, dest_props, edge_label, direction, opts \\ [])
      when is_atom(dest_label) and is_atom(edge_label) and is_atom(direction) and is_list(opts) do
    {src_pattern, src_params} = Cypher.parameterized_node(:s, List.wrap(src_label), src_props)
    {dest_pattern, dest_params} = Cypher.parameterized_node(:d, [dest_label], dest_props)
    {guard_clauses, guard_params} = source_guard_where(Keyword.get(opts, :guard, []))

    path_pattern = src_pattern <> Cypher.relationship(:r, edge_label, direction) <> dest_pattern

    %__MODULE__{
      clauses:
        [%Match{pattern: path_pattern}] ++
          guard_clauses ++
          [
            %Delete{items: ["r"]},
            %Return{items: ["s", "d"]}
          ],
      params: src_params |> Map.merge(dest_params) |> Map.merge(guard_params)
    }
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp labels_string(label) when is_list(label), do: Enum.join(label, ":")

  defp guard_condition(variable, edge_label, direction, dest_label) do
    rel =
      case direction do
        :outgoing -> "-[:#{edge_label}]->"
        :incoming -> "<-[:#{edge_label}]-"
        _ -> "-[:#{edge_label}]-"
      end

    "NOT (#{variable})#{rel}(:#{dest_label})"
  end

  # A `changeset.filter` guard (#368) on the source alias `:s` of a relate/unrelate
  # render — a `WHERE` placed immediately after the source `MATCH`, so a guard miss
  # yields zero rows (no MERGE/DELETE) and the caller raises `StaleRecord`. Params
  # are `g_`-prefixed so they can't collide with the `s_`/`d_` pattern params.
  defp source_guard_where([]), do: {[], %{}}

  defp source_guard_where(conditions) do
    {where_string, params} = build_conditions(:s, conditions, param_prefix: "g_")
    {[%Where{conditions: [where_string]}], params}
  end

  defp build_dest_conditions([]), do: {[], %{}}

  defp build_dest_conditions(dest_conditions) do
    {cond_strings, params} =
      dest_conditions
      |> Enum.with_index()
      |> Enum.reduce({[], %{}}, fn {{prop, val}, idx}, {parts, params} ->
        key = "agg_filter_#{idx}"
        {["d.#{prop} = $#{key}" | parts], Map.put(params, key, val)}
      end)

    {[%Where{conditions: Enum.reverse(cond_strings)}], params}
  end

  defp build_conditions(variable, conditions, opts) do
    param_prefix = Keyword.get(opts, :param_prefix, "")

    conditions
    |> Enum.with_index()
    |> Enum.reduce({"", %{}}, fn {{prop, op, val, ci?}, index}, {acc_str, acc_params} ->
      {expr, new_params} =
        cond do
          op == :is_nil ->
            {Cypher.expression(variable, prop, "is_nil", val), acc_params}

          op == :st_contains_box ->
            # Value is a {sw, ne} tuple of Bolty Points — the bbox corners
            # the caller wants to test for containment via two ANDed
            # `point.withinBBox` calls. The caller derives these from
            # whatever Geo struct it has (a Polygon's exterior ring, etc.).
            {sw, ne} = val
            prop_seg = Cypher.sanitize_param(prop)
            sw_key = "#{param_prefix}#{variable}_#{prop_seg}_#{index}_sw"
            ne_key = "#{param_prefix}#{variable}_#{prop_seg}_#{index}_ne"
            expr = Cypher.expression(variable, prop, "within_bbox_box", {"$#{sw_key}", "$#{ne_key}"})
            params = acc_params |> Map.put(sw_key, sw) |> Map.put(ne_key, ne)
            {expr, params}

          op == :st_distance ->
            {comp_op_atom, test_point, threshold} = val
            prop_seg = Cypher.sanitize_param(prop)
            test_key = "#{param_prefix}#{variable}_#{prop_seg}_#{index}_test"
            thresh_key = "#{param_prefix}#{variable}_#{prop_seg}_#{index}_t"
            expr = Cypher.expression(variable, prop, "st_distance", {convert_operator(comp_op_atom), "$#{test_key}", "$#{thresh_key}"})
            params = acc_params |> Map.put(test_key, test_point) |> Map.put(thresh_key, threshold)
            {expr, params}

          op == :st_dwithin ->
            {test_point, threshold} = val
            prop_seg = Cypher.sanitize_param(prop)
            test_key = "#{param_prefix}#{variable}_#{prop_seg}_#{index}_test"
            thresh_key = "#{param_prefix}#{variable}_#{prop_seg}_#{index}_d"
            expr = Cypher.expression(variable, prop, "dwithin", {"$#{test_key}", "$#{thresh_key}"})
            params = acc_params |> Map.put(test_key, test_point) |> Map.put(thresh_key, threshold)
            {expr, params}

          op in [:vector_similarity, :vector_cosine_distance] ->
            {comp_op_atom, query_vec, threshold} = val
            prop_seg = Cypher.sanitize_param(prop)
            vec_key = "#{param_prefix}#{variable}_#{prop_seg}_#{index}_vec"
            thresh_key = "#{param_prefix}#{variable}_#{prop_seg}_#{index}_t"
            expr = Cypher.expression(variable, prop, Atom.to_string(op), {convert_operator(comp_op_atom), "$#{vec_key}", "$#{thresh_key}"})
            params = acc_params |> Map.put(vec_key, query_vec) |> Map.put(thresh_key, threshold)
            {expr, params}

          true ->
            prop_seg = Cypher.sanitize_param(prop)
            param_key = "#{param_prefix}#{variable}_#{prop_seg}_#{index}"
            expr = Cypher.expression(variable, prop, convert_operator(op), "$#{param_key}", case_insensitive?: ci?)
            {expr, Map.put(acc_params, param_key, val)}
        end

      combined = if acc_str == "", do: expr, else: "#{acc_str} AND #{expr}"
      {combined, new_params}
    end)
  end

  defp convert_operator(:==), do: "="
  defp convert_operator(:!=), do: "<>"
  defp convert_operator(:in), do: "IN"
  defp convert_operator(:<=), do: "<="
  defp convert_operator(:<), do: "<"
  defp convert_operator(:>), do: ">"
  defp convert_operator(:>=), do: ">="
  defp convert_operator(:contains), do: "contains"
  defp convert_operator(:st_contains), do: "within_bbox"
  defp convert_operator(:st_contains_box), do: "within_bbox_box"
  defp convert_operator(:st_dwithin), do: "dwithin"

  defp build_agg_path(path_segments) do
    last_idx = length(path_segments) - 1

    path_segments
    |> Enum.with_index()
    |> Enum.reduce("", fn {{edge_label, direction, dest_label}, i}, acc ->
      node_var = if i == last_idx, do: "d", else: "h#{i}"

      rel =
        case direction do
          :outgoing -> "-[:#{edge_label}]->"
          :incoming -> "<-[:#{edge_label}]-"
          _ -> "-[:#{edge_label}]-"
        end

      node = if dest_label, do: "(#{node_var}:#{dest_label})", else: "(#{node_var})"
      acc <> rel <> node
    end)
  end

  # `node_var` is the node the aggregate runs over — `"d"` for a relationship
  # traversal, `"s"` for a root-node aggregate (empty relationship path, #291).
  defp aggregate_expr(kind, field, name, uniq?, node_var \\ "d") do
    distinct = if uniq?, do: "DISTINCT ", else: ""
    field_ref = if field, do: "#{node_var}.#{field}", else: node_var

    fn_str =
      case kind do
        :count -> "COUNT(#{distinct}#{node_var})"
        :exists -> "COUNT(#{node_var}) > 0"
        :sum -> "sum(#{distinct}#{field_ref})"
        :avg -> "avg(#{distinct}#{field_ref})"
        :min -> "min(#{field_ref})"
        :max -> "max(#{field_ref})"
        :list -> "collect(#{distinct}#{field_ref})"
        :first -> "head(collect(#{field_ref}))"
      end

    "#{fn_str} AS `#{name}`"
  end
end
