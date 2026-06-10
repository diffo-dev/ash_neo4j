# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Cypher do
  @moduledoc """
  AshNeo4j Cypher
  Functions for converting Elixir data structures to Cypher query components and running Cypher queries against a Neo4j database.
  Ideally has no specific knowledge of Ash

  """

  require Logger

  alias AshNeo4j.BoltyHelper

  alias AshNeo4j.Cypher.{
    Query,
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
    Limit,
    Call
  }

  # World-extent WGS-84 corners, used to rewrite bbox-containment predicates
  # into index-servable range scans on the indexed companion corners (#311).
  # `point.withinBBox(indexedCorner, worldSW, p)` reads as `indexedCorner <= p`
  # and is served by the POINT index (NodeIndexSeekByRange); the natural
  # `point.withinBBox(p, n.bbSW, n.bbNE)` form has the indexed properties as
  # the box, not the probe, so it can only be a full scan.
  @world_sw "point({longitude: -180, latitude: -90})"
  @world_ne "point({longitude: 180, latitude: 90})"

  @spec remove_properties(atom(), maybe_improper_list()) :: binary()
  @doc """
  Converts a list of property names into a remove properties string.
  The list is converted to a string in the format `n.key1, n.key2`.

  ## Examples
  ```
  iex> AshNeo4j.Cypher.remove_properties(:n, [:born, :bafta_winner])
  "n.born, n.bafta_winner"
  ```
  """
  def remove_properties(label, names) when is_atom(label) and is_list(names) do
    names
    |> Enum.map_join(", ", fn name -> "#{label}.#{name}" end)
  end

  @doc """
  Converts a node variable, label, predicates and operator to cypher expression

  ## Examples
  ```
  iex> AshNeo4j.Cypher.expression(:s, "name", "IN", "[$s_name_0]")
  "s.name IN [$s_name_0]"
  iex> AshNeo4j.Cypher.expression(:s, "name", "is_nil", true)
  "s.name IS NULL"
  iex> AshNeo4j.Cypher.expression(:s, "name", "is_nil", false)
  "s.name IS NOT NULL"
  iex> AshNeo4j.Cypher.expression(:s, "name", "contains", "$s_name_0")
  "s.name CONTAINS $s_name_0"
  iex> AshNeo4j.Cypher.expression(:s, "name", "contains", "$s_name_0", case_insensitive?: true)
  "toLower(s.name) CONTAINS toLower($s_name_0)"
  iex> AshNeo4j.Cypher.expression(:s, "name", "=", "$s_name_0", case_insensitive?: true)
  "toLower(s.name) = toLower($s_name_0)"
  iex> AshNeo4j.Cypher.expression(:n, "bounds", "within_bbox", "$test_point")
  "point.withinBBox(n.`bounds.bbSW`, point({longitude: -180, latitude: -90}), $test_point) AND point.withinBBox(n.`bounds.bbNE`, $test_point, point({longitude: 180, latitude: 90}))"
  iex> AshNeo4j.Cypher.expression(:n, "bounds", "within_bbox_box", {"$inner_sw", "$inner_ne"})
  "point.withinBBox(n.`bounds.bbSW`, point({longitude: -180, latitude: -90}), $inner_sw) AND point.withinBBox(n.`bounds.bbNE`, $inner_ne, point({longitude: 180, latitude: 90}))"
  iex> AshNeo4j.Cypher.expression(:n, "location", "st_distance", {"<", "$test_point", "$threshold"})
  "point.distance(n.location, $test_point) < $threshold"
  iex> AshNeo4j.Cypher.expression(:n, "location", "dwithin", {"$test_point", "$threshold"})
  "point.distance(n.location, $test_point) <= $threshold"
  iex> AshNeo4j.Cypher.expression(:s, "embedding", "vector_similarity", {">", "$s_embedding_0_vec", "$s_embedding_0_t"})
  "vector.similarity.cosine(s.embedding, $s_embedding_0_vec) > $s_embedding_0_t"
  iex> AshNeo4j.Cypher.expression(:s, "embedding", "vector_cosine_distance", {"<", "$s_embedding_0_vec", "$s_embedding_0_t"})
  "(2.0 * (1.0 - vector.similarity.cosine(s.embedding, $s_embedding_0_vec))) < $s_embedding_0_t"
  ```
  """
  def expression(variable, left, operator, right, opts \\ [])
      when is_atom(variable) and is_bitstring(left) and is_bitstring(operator) do
    case_insensitive? = Keyword.get(opts, :case_insensitive?, false)

    cond do
      operator == "IN" && right == "[]" ->
        "#{variable}.#{left} IS NULL"

      operator == "is_nil" && right ->
        "#{variable}.#{left} IS NULL"

      operator == "is_nil" && !right ->
        "#{variable}.#{left} IS NOT NULL"

      operator == "within_bbox" ->
        # P ∈ [bbSW, bbNE] ⟺ bbSW ≤ P AND bbNE ≥ P. Probing the indexed corners
        # against world-extent boxes keeps the indexed properties as the probe,
        # so the POINT index serves both ranges (#311).
        bb_sw = "#{variable}.`#{left}.bbSW`"
        bb_ne = "#{variable}.`#{left}.bbNE`"

        "point.withinBBox(#{bb_sw}, #{@world_sw}, #{right}) AND " <>
          "point.withinBBox(#{bb_ne}, #{right}, #{@world_ne})"

      operator == "within_bbox_box" ->
        {sw_ref, ne_ref} = right
        # Test box ⊆ attr box ⟺ attr.bbSW ≤ test.sw AND attr.bbNE ≥ test.ne —
        # again expressed as indexed-corner range scans (#311).
        bb_sw = "#{variable}.`#{left}.bbSW`"
        bb_ne = "#{variable}.`#{left}.bbNE`"

        "point.withinBBox(#{bb_sw}, #{@world_sw}, #{sw_ref}) AND " <>
          "point.withinBBox(#{bb_ne}, #{ne_ref}, #{@world_ne})"

      operator == "st_distance" ->
        {comp_op, test_ref, threshold_ref} = right
        "point.distance(#{variable}.#{quote_if_dotted(left)}, #{test_ref}) #{comp_op} #{threshold_ref}"

      operator == "dwithin" ->
        {test_ref, threshold_ref} = right
        "point.distance(#{variable}.#{quote_if_dotted(left)}, #{test_ref}) <= #{threshold_ref}"

      operator == "vector_similarity" ->
        {comp_op, vec_ref, threshold_ref} = right
        "#{vector_scalar(:vector_similarity, variable, left, vec_ref)} #{comp_op} #{threshold_ref}"

      operator == "vector_cosine_distance" ->
        {comp_op, vec_ref, threshold_ref} = right
        "#{vector_scalar(:vector_cosine_distance, variable, left, vec_ref)} #{comp_op} #{threshold_ref}"

      case_insensitive? ->
        "toLower(#{variable}.#{left}) #{String.upcase(operator)} toLower(#{right})"

      true ->
        "#{variable}.#{left} #{String.upcase(operator)} #{right}"
    end
  end

  @doc """
  Bare scalar Cypher for a vector function, e.g. for use in `ORDER BY`.

  `vec_ref` is the parameter reference holding the query embedding (`"$q"`).
  `vector_similarity` is Neo4j's normalised cosine similarity in `[0, 1]`
  (higher = closer); `vector_cosine_distance` rescales it to pgvector-style
  distance in `[0, 2]` (lower = closer) via `2 * (1 - similarity)`.

  ## Examples
  ```
  iex> AshNeo4j.Cypher.vector_scalar(:vector_similarity, :s, "embedding", "$q")
  "vector.similarity.cosine(s.embedding, $q)"
  iex> AshNeo4j.Cypher.vector_scalar(:vector_cosine_distance, :s, "embedding", "$q")
  "(2.0 * (1.0 - vector.similarity.cosine(s.embedding, $q)))"
  ```
  """
  def vector_scalar(:vector_similarity, variable, prop, vec_ref) do
    "vector.similarity.cosine(#{variable}.#{prop}, #{vec_ref})"
  end

  def vector_scalar(:vector_cosine_distance, variable, prop, vec_ref) do
    "(2.0 * (1.0 - vector.similarity.cosine(#{variable}.#{prop}, #{vec_ref})))"
  end

  @doc """
  Converts a node variable and labels to basic cypher node expression.

  ## Examples
  ```
  iex> AshNeo4j.Cypher.node(:s, [:Actor])
  "(s:Actor)"
  ```
  """
  def node(variable, labels) when is_atom(variable) and is_list(labels) do
    "(#{variable}:#{Enum.join(labels, ":")})"
  end

  @doc """
  Converts a node variable, labels and optional property map to cypher properties string and variable prefixed parameters map.

  ## Examples
  ```
  iex> AshNeo4j.Cypher.parameterized_node(:s, [:Actor])
  {"(s:Actor)", %{}}
  iex> AshNeo4j.Cypher.parameterized_node(:s, [:Cinema, :Actor], %{name: "Bill Nighy"})
  {"(s:Cinema:Actor {name: $s_name})", %{"s_name" =>"Bill Nighy"}}
  ```
   Note: the properties map is converted to parameter names by prefixing the keys with `$<variable>`, and the original values are returned in a separate map for use as query parameters.
  """
  def parameterized_node(variable, labels, properties \\ %{})
      when is_atom(variable) and is_list(labels) and is_map(properties) do
    if properties == %{} do
      {node(variable, labels), %{}}
    else
      {property_cypher, parameters} = parameterized_properties(variable, properties)
      label_string = Enum.join(labels, ":")
      {"(#{variable}:#{label_string} #{property_cypher})", parameters}
    end
  end

  @doc """
  Converts a node variable and optional property map to cypher properties string and variable prefixed parameters map.

  ## Examples
  ```
  iex> AshNeo4j.Cypher.parameterized_properties(:s)
  {"{}", %{}}
  iex> AshNeo4j.Cypher.parameterized_properties(:s, %{name: "Bill Nighy"})
  {"{name: $s_name}", %{"s_name" =>"Bill Nighy"}}
  ```
  """
  def parameterized_properties(variable, properties \\ %{}) when is_atom(variable) and is_map(properties) do
    parameterized_properties =
      properties
      |> Enum.map_join(", ", fn {k, _v} -> "#{quote_if_dotted(k)}: $#{variable}_#{sanitize_param(k)}" end)

    parameters = build_parameters(variable, properties)

    {"{#{parameterized_properties}}", parameters}
  end

  @doc """
  Backtick-quotes a property name if it contains a dot, so that Neo4j
  parses it as a single property reference rather than a nested-property
  access. e.g. `"location.point"` → `` "`location.point`" ``.
  """
  def quote_if_dotted(name) do
    s = to_string(name)
    if String.contains?(s, "."), do: "`#{s}`", else: s
  end

  @doc """
  Rewrites dots in a name as underscores so it is safe to use as a
  Cypher parameter key. Neo4j parses `$foo.bar` as the parameter `$foo`
  followed by a `.bar` property access, so the dot has to go.
  """
  def sanitize_param(name) do
    to_string(name) |> String.replace(".", "_")
  end

  @doc """
  Converts a node variable and optional property map to cypher WHERE conditions and variable prefixed parameters map.
  ## Examples
  ```
  iex> AshNeo4j.Cypher.parameterized_conditions(:n, %{name: "Bill Nighy"})
  {"n.name = $n_name", %{"n_name" => "Bill Nighy"}}
  iex> AshNeo4j.Cypher.parameterized_conditions(:n, %{name: "Bill Nighy", age: 72})
  {"n.name = $n_name AND n.age = $n_age", %{"n_name" => "Bill Nighy", "n_age" => 72}}
  ```
  """
  def parameterized_conditions(variable, properties \\ %{}) when is_atom(variable) and is_map(properties) do
    conditions =
      Enum.map_join(properties, " AND ", fn {k, _v} ->
        "#{variable}.#{k} = $#{variable}_#{k}"
      end)

    parameters = build_parameters(variable, properties)

    {conditions, parameters}
  end

  defp build_parameters(variable, properties) do
    Map.new(properties, fn {k, v} -> {"#{variable}_#{sanitize_param(k)}", v} end)
  end

  defp sandboxed_query(cypher, params) do
    case Process.get(:ash_neo4j_tx_stack, []) do
      [conn | _] ->
        Bolty.query(conn, cypher, params)

      [] ->
        case AshNeo4j.Sandbox.run(cypher, params) do
          nil -> Bolty.query(BoltyHelper.current_pool(), cypher, params)
          result -> result
        end
    end
  end

  @spec relationship(atom(), atom()) :: <<_::32, _::_*8>>
  @doc """
  Converts a relationship variable, label and optional direction to cypher relationship.

  ## Examples
  ```
  iex> AshNeo4j.Cypher.relationship(:r, :ACTED_IN, :outgoing)
  "-[r:ACTED_IN]->"
  iex> AshNeo4j.Cypher.relationship(:r, :ACTED_IN, :incoming)
  "<-[r:ACTED_IN]-"
  iex> AshNeo4j.Cypher.relationship(:r, :KNOWS)
  "-[r:KNOWS]-"
  ```
  """
  def relationship(variable, label, direction \\ nil)
      when is_atom(variable) and is_atom(label) and is_atom(direction) do
    if variable == nil do
      case direction do
        :outgoing ->
          "-[#{label}]->"

        :incoming ->
          "<-[#{label}]-"

        _ ->
          "-[#{label}]-"
      end
    else
      case direction do
        :outgoing ->
          "-[#{variable}:#{label}]->"

        :incoming ->
          "<-[#{variable}:#{label}]-"

        _ ->
          "-[#{variable}:#{label}]-"
      end
    end
  end

  def relationship(nil), do: "-[r]-"

  @doc """
  Renders a `%Cypher.Query{}` to a `{cypher_string, params}` tuple.

  ## Examples
  ```
  iex> query = %AshNeo4j.Cypher.Query{
  ...>   clauses: [
  ...>     %AshNeo4j.Cypher.Match{pattern: "(s:Actor)"},
  ...>     %AshNeo4j.Cypher.Return{items: ["s"]},
  ...>     %AshNeo4j.Cypher.Limit{value: 5}
  ...>   ],
  ...>   params: %{}
  ...> }
  iex> AshNeo4j.Cypher.render(query)
  {"MATCH (s:Actor) RETURN s LIMIT 5", %{}}

  iex> query = %AshNeo4j.Cypher.Query{
  ...>   clauses: [
  ...>     %AshNeo4j.Cypher.Call{
  ...>       branches: [
  ...>         "MATCH (s:Place) WHERE s.uuid = $b0_s_uuid_0 RETURN s",
  ...>         "MATCH (s:Place) WHERE s.uuid = $b1_s_uuid_0 RETURN s"
  ...>       ],
  ...>       union_type: :union_all
  ...>     },
  ...>     %AshNeo4j.Cypher.OptionalMatch{pattern: "(s)-[r]-(d)"},
  ...>     %AshNeo4j.Cypher.Return{items: ["s", "r", "d"]}
  ...>   ],
  ...>   params: %{"b0_s_uuid_0" => "x", "b1_s_uuid_0" => "y"}
  ...> }
  iex> {cypher, _params} = AshNeo4j.Cypher.render(query)
  iex> cypher
  "CALL { MATCH (s:Place) WHERE s.uuid = $b0_s_uuid_0 RETURN s UNION ALL MATCH (s:Place) WHERE s.uuid = $b1_s_uuid_0 RETURN s } OPTIONAL MATCH (s)-[r]-(d) RETURN s, r, d"
  ```
  """
  def render(query, opts \\ [])

  def render(%Query{clauses: clauses, params: params}, opts) do
    # The CYPHER 25 language selector may appear only once, at the very start of
    # a query — never inside a subquery. Branches assembled into a `CALL { … }`
    # block are rendered with `prefix?: false` so only the outer query carries
    # the prefix (#299).
    prefix = if Keyword.get(opts, :prefix?, true), do: cypher25_prefix(), else: ""
    {prefix <> Enum.map_join(clauses, " ", &render_clause/1), params}
  end

  defp cypher25_prefix, do: if(BoltyHelper.cypher25?(), do: "CYPHER 25 ", else: "")

  defp render_clause(%Match{pattern: p}), do: "MATCH #{p}"
  defp render_clause(%OptionalMatch{pattern: p}), do: "OPTIONAL MATCH #{p}"
  defp render_clause(%Create{pattern: p}), do: "CREATE #{p}"
  defp render_clause(%Merge{pattern: p}), do: "MERGE #{p}"
  defp render_clause(%Where{conditions: conds}), do: "WHERE #{Enum.join(conds, " AND ")}"
  defp render_clause(%With{items: items}), do: "WITH #{Enum.join(items, ", ")}"
  defp render_clause(%Set{expression: e}), do: "SET #{e}"
  defp render_clause(%Remove{items: items}), do: "REMOVE #{Enum.join(items, ", ")}"
  defp render_clause(%Delete{items: items}), do: "DELETE #{Enum.join(items, ", ")}"
  defp render_clause(%DetachDelete{items: items}), do: "DETACH DELETE #{Enum.join(items, ", ")}"
  defp render_clause(%Return{items: items}), do: "RETURN #{Enum.join(items, ", ")}"
  defp render_clause(%Skip{value: n}), do: "SKIP #{n}"
  defp render_clause(%Limit{value: n}), do: "LIMIT #{n}"

  defp render_clause(%Call{branches: branches, union_type: union_type}) do
    joiner =
      case union_type do
        :union -> " UNION "
        :union_all -> " UNION ALL "
      end

    "CALL { #{Enum.join(branches, joiner)} }"
  end

  defp render_clause(%AshNeo4j.Cypher.CallSubquery{body: body}), do: "CALL { #{body} }"

  defp render_clause(%OrderBy{terms: terms}) do
    "ORDER BY " <>
      Enum.map_join(terms, ", ", fn
        {prop, :desc} -> "#{prop} DESC"
        {prop, _} -> "#{prop} ASC"
      end)
  end

  @doc """
  Raises `AshNeo4j.Error.RequiresCypher25` when the connected server does not
  support Cypher 25 (negotiated server version < 2025.06). Call at the top of
  any function that emits Cypher 25-only syntax.
  """
  def require_cypher25!() do
    unless BoltyHelper.cypher25?() do
      raise AshNeo4j.Error.RequiresCypher25
    end
  end

  @doc """
  Runs some cypher

  ## Examples
  ```
  iex> cypher = "CREATE (n:Actor {name: 'Bill Nighy', born: 1949, bafta_winner: true}) RETURN n"
  iex> {result, _} = AshNeo4j.Cypher.run(cypher)
  iex> result
  :ok
  iex> cypher = "MATCH (n:Actor {name: $name}) RETURN n"
  iex> params = %{name: "Bill Nighy"}
  iex> {result, _} = AshNeo4j.Cypher.run(cypher, params)
  iex> result
  :ok
  ```
  """
  def run(%Query{} = query) do
    {cypher, params} = render(query)
    run(cypher, params)
  end

  def run(cypher, params \\ %{}) when is_bitstring(cypher) do
    cypher = cypher25_prefix() <> cypher

    Logger.debug("""
    AshNeo4j.Cypher: run(#{cypher}, #{inspect(params)})
    """)

    bolty_result = sandboxed_query(cypher, params)

    if elem(bolty_result, 0) == :ok do
      Logger.debug("""
      AshNeo4j.Cypher: run result #{inspect(elem(bolty_result, 1).results)}
      """)
    end

    bolty_result
  end

  def run_expecting_deletions(%Query{} = query) do
    {cypher, params} = render(query)
    run_expecting_deletions(cypher, params)
  end

  def run_expecting_deletions(cypher, params \\ %{}) when is_bitstring(cypher) do
    cypher = cypher25_prefix() <> cypher
    Logger.debug("AshNeo4.Cypher: run_expecting_deletions(#{cypher})")

    bolty_result = sandboxed_query(cypher, params)

    if elem(bolty_result, 0) == :ok do
      response = elem(bolty_result, 1)

      deleted_nodes =
        case response.stats do
          [] ->
            0

          %{} ->
            Map.get(response.stats, "nodes-deleted", 0)
        end

      if deleted_nodes == 0 do
        Logger.error("AshNeo4j.Cypher: nothing deleted")
        {:error, "nothing deleted"}
      else
        Logger.debug("AshNeo4j.Cypher: run_expecting_deletions deleted #{deleted_nodes} nodes")
        bolty_result
      end
    else
      bolty_result
    end
  end
end
