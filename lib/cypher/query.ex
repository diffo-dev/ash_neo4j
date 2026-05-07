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
  Typed representation of a Cypher query, and builders for constructing common read patterns.

  The struct holds an ordered list of typed clause structs and a params map.
  Callers build a query via the builder functions, then pass it to
  `AshNeo4j.Cypher.render/1` or `AshNeo4j.Cypher.run/1`.

  ## Clause structs

  - `AshNeo4j.Cypher.Match` — `MATCH <pattern>`
  - `AshNeo4j.Cypher.OptionalMatch` — `OPTIONAL MATCH <pattern>`
  - `AshNeo4j.Cypher.Where` — `WHERE cond1 AND cond2 ...`
  - `AshNeo4j.Cypher.With` — `WITH item1, item2 ...`
  - `AshNeo4j.Cypher.Return` — `RETURN item1, item2 ...`
  - `AshNeo4j.Cypher.OrderBy` — `ORDER BY prop ASC/DESC ...`
  - `AshNeo4j.Cypher.Skip` — `SKIP n`
  - `AshNeo4j.Cypher.Limit` — `LIMIT n`
  """

  alias AshNeo4j.Cypher
  alias AshNeo4j.Cypher.{Match, OptionalMatch, Where, With, Return, OrderBy, Skip, Limit}

  @type clause ::
          Match.t()
          | OptionalMatch.t()
          | Where.t()
          | With.t()
          | Return.t()
          | OrderBy.t()
          | Skip.t()
          | Limit.t()

  @type t :: %__MODULE__{clauses: [clause()], params: map()}

  defstruct clauses: [], params: %{}

  @typedoc """
  A single property filter condition. Fields:
  - `property` — Neo4j property name string
  - `operator` — operator atom (e.g. `:==`, `:in`, `:contains`, `:is_nil`)
  - `value` — the right-hand value; boolean for `:is_nil`, actual value otherwise
  - `case_insensitive?` — wrap property and value in `toLower/1`
  """
  @type condition :: {property :: String.t(), operator :: atom(), value :: any(), case_insensitive? :: boolean()}

  @doc """
  Builds a node read query: `MATCH (s:Label) OPTIONAL MATCH (s)-[r]-(d) RETURN s, r, d`.
  """
  @spec node_read(atom()) :: t()
  def node_read(label) when is_atom(label) do
    %__MODULE__{
      clauses: [
        %Match{pattern: Cypher.node(:s, [label])},
        %OptionalMatch{pattern: "(s)-[r]-(d)"},
        %Return{items: ["s", "r", "d"]}
      ]
    }
  end

  @doc """
  Builds a filtered node read query:
  `MATCH (s:Label) WHERE <conditions> OPTIONAL MATCH (s)-[r]-(d) RETURN s, r, d`.

  `conditions` is a list of `t:condition/0` tuples. Returns `node_read/1` when the list is empty.
  """
  @spec node_read_filtered(atom(), [condition()]) :: t()
  def node_read_filtered(label, []) when is_atom(label), do: node_read(label)

  def node_read_filtered(label, conditions) when is_atom(label) and is_list(conditions) do
    {where_string, params} = build_conditions(:s, conditions)

    %__MODULE__{
      clauses: [
        %Match{pattern: Cypher.node(:s, [label])},
        %Where{conditions: [where_string]},
        %OptionalMatch{pattern: "(s)-[r]-(d)"},
        %Return{items: ["s", "r", "d"]}
      ],
      params: params
    }
  end

  @doc """
  Builds a relationship-filtered node read query:

      MATCH (s:SrcLabel)-[r:EdgeLabel]->(d:DestLabel)
      WHERE d.dest_property <op> $param
      WITH s MATCH (s)-[r0]-(d0) RETURN s, r0, d0
  """
  @spec relationship_read(atom(), atom(), atom(), atom(), String.t(), atom(), any()) :: t()
  def relationship_read(src_label, edge_label, direction, dest_label, dest_property, operator, value)
      when is_atom(src_label) and is_atom(edge_label) and is_atom(direction) and is_atom(dest_label) do
    param_key = "d_#{dest_property}"

    match_pattern =
      Cypher.node(:s, [src_label]) <>
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
  Appends an `ORDER BY` clause. `terms` is a list of `{property_name, :asc | :desc}` pairs
  where `property_name` is the Neo4j property name (not prefixed with a variable).
  The source node variable `s` is assumed. No-op when `terms` is empty.
  """
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

  # Builds a WHERE string and params map from a list of conditions.
  # For :is_nil, passes the boolean directly to expression/5 and stores no param.
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
end
