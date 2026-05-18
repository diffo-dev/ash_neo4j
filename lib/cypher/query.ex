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

defmodule AshNeo4j.Cypher.Limit do
  @moduledoc "LIMIT clause."
  @type t :: %__MODULE__{value: pos_integer()}
  defstruct [:value]
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
    Remove,
    Delete,
    DetachDelete,
    Return,
    OrderBy,
    Skip,
    Limit
  }

  @type clause ::
          Match.t()
          | OptionalMatch.t()
          | Create.t()
          | Merge.t()
          | Where.t()
          | With.t()
          | Set.t()
          | Remove.t()
          | Delete.t()
          | DetachDelete.t()
          | Return.t()
          | OrderBy.t()
          | Skip.t()
          | Limit.t()

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
  @spec node_read_filtered(atom() | [atom()], [condition()]) :: t()
  def node_read_filtered(label, []), do: node_read(label)

  def node_read_filtered(label, conditions) when is_list(conditions) do
    {where_string, params} = build_conditions(:s, conditions)

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

  @doc "Appends an `ORDER BY` clause. No-op when `terms` is empty."
  @spec add_order_by(t(), [{atom() | String.t(), :asc | :desc}]) :: t()
  def add_order_by(%__MODULE__{} = query, []), do: query

  def add_order_by(%__MODULE__{} = query, terms) when is_list(terms) do
    order_terms = Enum.map(terms, fn {prop, order} -> {"s.#{prop}", order} end)
    %{query | clauses: query.clauses ++ [%OrderBy{terms: order_terms}]}
  end

  @doc "Appends a `SKIP` clause. No-op when `n` is `nil` or `0`."
  @spec add_skip(t(), non_neg_integer() | nil) :: t()
  def add_skip(%__MODULE__{} = query, n) when n in [nil, 0], do: query
  def add_skip(%__MODULE__{} = query, n), do: %{query | clauses: query.clauses ++ [%Skip{value: n}]}

  @doc "Appends a `LIMIT` clause. No-op when `n` is `nil`."
  @spec add_limit(t(), pos_integer() | nil) :: t()
  def add_limit(%__MODULE__{} = query, nil), do: query
  def add_limit(%__MODULE__{} = query, n), do: %{query | clauses: query.clauses ++ [%Limit{value: n}]}

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
        ] ++ dest_where ++ [%Return{items: [expr]}],
      params: Map.merge(%{"agg_ids" => ids}, dest_params)
    }
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
  `MATCH (n:L1:L2 {match_props}) SET n += {set_props} REMOVE n.p1, n.p2 RETURN n`

  Handles all combinations of empty/non-empty set_props and remove_props.
  """
  @spec update_node(atom() | [atom()], map(), map(), [atom()]) :: t()
  def update_node(label, match_props, set_props, remove_props \\ [])
      when is_map(match_props) and is_map(set_props) and is_list(remove_props) do
    {match_pattern, match_params} = Cypher.parameterized_node(:n, List.wrap(label), match_props)
    {props_cypher, set_params} = Cypher.parameterized_properties(:n, set_props)

    set_clauses = if map_size(set_props) > 0, do: [%Set{expression: "n += #{props_cypher}"}], else: []
    remove_clauses = if remove_props != [], do: [%Remove{items: Enum.map(remove_props, &"n.#{&1}")}], else: []

    %__MODULE__{
      clauses: [%Match{pattern: match_pattern}] ++ set_clauses ++ remove_clauses ++ [%Return{items: ["n"]}],
      params: Map.merge(match_params, set_params)
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
  `MATCH (s:SrcLabel {s_props}) OPTIONAL MATCH (d:DestLabel {d_props}) MERGE (s)-[r:EDGE]->(d) RETURN s, r, d`
  """
  @spec relate(atom() | [atom()], map(), atom() | [atom()], map(), atom(), atom()) :: t()
  def relate(src_label, src_props, dest_label, dest_props, edge_label, direction)
      when is_atom(edge_label) and is_atom(direction) do
    {src_pattern, src_params} = Cypher.parameterized_node(:s, List.wrap(src_label), src_props)
    {dest_pattern, dest_params} = Cypher.parameterized_node(:d, List.wrap(dest_label), dest_props)

    %__MODULE__{
      clauses: [
        %Match{pattern: src_pattern},
        %OptionalMatch{pattern: dest_pattern},
        %Merge{pattern: "(s)" <> Cypher.relationship(:r, edge_label, direction) <> "(d)"},
        %Return{items: ["s", "r", "d"]}
      ],
      params: Map.merge(src_params, dest_params)
    }
  end

  @doc """
  Relates two nodes, first removing any existing edge of the same type from the source.

      MATCH (s:SrcLabel {s_props})
      WITH s OPTIONAL MATCH (s)-[r0:EDGE]->(d0:DestLabel)
      DELETE r0 WITH s MATCH (d:DestLabel {d_props})
      MERGE (s)-[r:EDGE]->(d) RETURN s, r, d
  """
  @spec relate_unrelating_source(atom() | [atom()], map(), atom(), map(), atom(), atom()) :: t()
  def relate_unrelating_source(src_label, src_props, dest_label, dest_props, edge_label, direction)
      when is_atom(dest_label) and is_atom(edge_label) and is_atom(direction) do
    {src_pattern, src_params} = Cypher.parameterized_node(:s, List.wrap(src_label), src_props)
    {dest_pattern, dest_params} = Cypher.parameterized_node(:d, [dest_label], dest_props)

    %__MODULE__{
      clauses: [
        %Match{pattern: src_pattern},
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
      params: Map.merge(src_params, dest_params)
    }
  end

  @doc """
  Relates two nodes, first removing any existing edge of the same type pointing to the destination.

      MATCH (s:SrcLabel {s_props}) OPTIONAL MATCH (d:DestLabel {d_props})
      WITH s, d OPTIONAL MATCH (s0:SrcLabel)-[r0:EDGE]->(d) WHERE s0 <> s
      DELETE r0 WITH s, d MERGE (s)-[r:EDGE]->(d) RETURN s, r, d
  """
  @spec relate_unrelating_destination(atom() | [atom()], map(), atom(), map(), atom(), atom()) :: t()
  def relate_unrelating_destination(src_label, src_props, dest_label, dest_props, edge_label, direction)
      when is_atom(dest_label) and is_atom(edge_label) and is_atom(direction) do
    src_labels = List.wrap(src_label)
    {src_pattern, src_params} = Cypher.parameterized_node(:s, src_labels, src_props)
    {dest_pattern, dest_params} = Cypher.parameterized_node(:d, [dest_label], dest_props)

    %__MODULE__{
      clauses: [
        %Match{pattern: src_pattern},
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
      params: Map.merge(src_params, dest_params)
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
  @spec relate_unrelating_both(atom() | [atom()], map(), atom(), map(), atom(), atom()) :: t()
  def relate_unrelating_both(src_label, src_props, dest_label, dest_props, edge_label, direction)
      when is_atom(dest_label) and is_atom(edge_label) and is_atom(direction) do
    src_labels = List.wrap(src_label)
    {src_pattern, src_params} = Cypher.parameterized_node(:s, src_labels, src_props)
    {dest_pattern, dest_params} = Cypher.parameterized_node(:d, [dest_label], dest_props)

    %__MODULE__{
      clauses: [
        %Match{pattern: src_pattern},
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
      params: Map.merge(src_params, dest_params)
    }
  end

  @doc """
  `MATCH (s:SrcLabel {s_props})-[r:EDGE]->(d:DestLabel {d_props}) DELETE r RETURN s, d`
  """
  @spec unrelate(atom() | [atom()], map(), atom(), map(), atom(), atom()) :: t()
  def unrelate(src_label, src_props, dest_label, dest_props, edge_label, direction)
      when is_atom(dest_label) and is_atom(edge_label) and is_atom(direction) do
    {src_pattern, src_params} = Cypher.parameterized_node(:s, List.wrap(src_label), src_props)
    {dest_pattern, dest_params} = Cypher.parameterized_node(:d, [dest_label], dest_props)

    path_pattern = src_pattern <> Cypher.relationship(:r, edge_label, direction) <> dest_pattern

    %__MODULE__{
      clauses: [
        %Match{pattern: path_pattern},
        %Delete{items: ["r"]},
        %Return{items: ["s", "d"]}
      ],
      params: Map.merge(src_params, dest_params)
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

  defp build_conditions(variable, conditions) do
    conditions
    |> Enum.with_index()
    |> Enum.reduce({"", %{}}, fn {{prop, op, val, ci?}, index}, {acc_str, acc_params} ->
      {expr, new_params} =
        if op == :is_nil do
          {Cypher.expression(variable, prop, "is_nil", val), acc_params}
        else
          param_key = "#{variable}_#{prop}_#{index}"
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

      acc <> rel <> "(#{node_var}:#{dest_label})"
    end)
  end

  defp aggregate_expr(kind, field, name, uniq?) do
    distinct = if uniq?, do: "DISTINCT ", else: ""
    field_ref = if field, do: "d.#{field}", else: "d"

    fn_str =
      case kind do
        :count -> "COUNT(#{distinct}d)"
        :exists -> "COUNT(d) > 0"
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
