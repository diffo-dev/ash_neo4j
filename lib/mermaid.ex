# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Mermaid do
  @moduledoc """
  Render a graph query result as a [Mermaid flowchart](https://mermaid.js.org/syntax/flowchart.html)
  string.

  The input is what `AshNeo4j.Cypher.run/2` (and `AshNeo4j.Neo4jHelper`) return —
  a `%Bolty.Response{}` or the `{:ok, response}` tuple. The output is a plain
  string, with no `Kino` dependency, so it renders anywhere a Mermaid flowchart
  is accepted: `Kino.Mermaid.new/1` in the AshNeo4j livebook, Artefact import, or
  a Markdown fence.

  Graph values in the result rows are rendered structurally:

  - `%Bolty.Types.Node{}` → a flowchart node `n<id>["Label<br/>key: value"]`,
    showing its labels and stored (graph, not Ash-cast) properties.
  - `%Bolty.Types.Relationship{}` → a directed edge `n<start> -->|TYPE| n<end>`.
  - `%Bolty.Types.Path{}` → its nodes and relationships, with edge direction
    reconstructed from the path's traversal sequence.

  Nodes are de-duplicated by graph id, so the same node returned in several rows
  appears once. Scalars (strings, numbers, points, …) in the result are ignored —
  only graph entities are drawn.

  ## Options

  - `:direction` — flowchart direction, `"TD"` (default), `"LR"`, `"BT"`, `"RL"`.
  - `:properties` — `true` (default, all stored properties), `false` (labels
    only), or a list of property names to keep, in that order.

  ## Examples
  ```
  iex> node = %Bolty.Types.Node{id: 0, labels: ["Person"], properties: %{"name" => "Bill"}}
  iex> AshNeo4j.Mermaid.flowchart(%Bolty.Response{results: [%{"n" => node}]})
  "flowchart TD\\n    n0[\\"Person<br/>name: Bill\\"]"

  iex> a = %Bolty.Types.Node{id: 1, labels: ["Person"], properties: %{}}
  iex> b = %Bolty.Types.Node{id: 2, labels: ["Movie"], properties: %{}}
  iex> r = %Bolty.Types.Relationship{id: 9, type: "ACTED_IN", start: 1, end: 2}
  iex> AshNeo4j.Mermaid.flowchart({:ok, %Bolty.Response{results: [%{"a" => a, "r" => r, "b" => b}]}})
  "flowchart TD\\n    n1[\\"Person\\"]\\n    n2[\\"Movie\\"]\\n    n1 -->|ACTED_IN| n2"

  iex> node = %Bolty.Types.Node{id: 0, labels: ["Person"], properties: %{"name" => "Bill"}}
  iex> AshNeo4j.Mermaid.flowchart(%Bolty.Response{results: [%{"n" => node}]}, properties: false)
  "flowchart TD\\n    n0[\\"Person\\"]"
  ```
  """

  alias Bolty.Response
  alias Bolty.Types.{Node, Relationship}

  @indent "    "

  @doc """
  Renders a graph result as a Mermaid flowchart string. See the module docs for
  accepted inputs and options.
  """
  @spec flowchart(Response.t() | {:ok, Response.t()} | {:error, term()} | list(), keyword()) ::
          String.t()
  def flowchart(result, opts \\ [])

  def flowchart({:ok, %Response{} = response}, opts), do: flowchart(response, opts)

  def flowchart({:error, reason}, _opts) do
    raise ArgumentError, "AshNeo4j.Mermaid.flowchart/2 cannot render an error result: #{inspect(reason)}"
  end

  def flowchart(%Response{results: results}, opts), do: flowchart(results, opts)

  def flowchart(results, opts) when is_list(results) do
    direction = opts |> Keyword.get(:direction, "TD") |> to_string()

    {nodes, edges} = Enum.reduce(results, {[], []}, &collect/2)

    nodes = nodes |> Enum.reverse() |> Enum.uniq_by(&node_gid/1)
    edges = edges |> Enum.reverse() |> Enum.uniq()

    # Draw a placeholder for any edge endpoint whose node was not itself returned
    # (e.g. `MATCH ()-[r]->() RETURN r`), so the edge still connects.
    drawn = MapSet.new(nodes, &node_gid/1)

    placeholders =
      edges
      |> Enum.flat_map(fn {from, to, _label} -> [from, to] end)
      |> Enum.uniq()
      |> Enum.reject(&MapSet.member?(drawn, &1))
      |> Enum.map(&{:placeholder, &1})

    lines =
      ["flowchart #{direction}"] ++
        Enum.map(nodes ++ placeholders, &node_line(&1, opts)) ++
        Enum.map(edges, &edge_line/1)

    Enum.join(lines, "\n")
  end

  # --- live tap -------------------------------------------------------------

  @handler_id "ash_neo4j_mermaid_tap"
  @agent __MODULE__.Tap

  @doc """
  Starts capturing the most recent query result, for `last/1`.

  Attaches a `[:ash_neo4j, :query]` telemetry handler (see `AshNeo4j.Cypher.run/2`)
  that stashes the most recent successful `%Bolty.Response{}` *containing graph
  entities* (nodes/relationships/paths) in a small `Agent` — so a plain scalar or
  stat query between graph queries won't clobber the captured view. Idempotent.
  Pair with `untap/0`. Intended for interactive use (livebook, IEx); the rest of
  the library never attaches a handler, so without `tap/0` the seam costs nothing.

  ## Example
      AshNeo4j.Mermaid.tap()
      AshNeo4j.Cypher.run("MATCH (n:Person)-[r]->(m) RETURN n, r, m")
      AshNeo4j.Mermaid.last() |> Kino.Mermaid.new()
  """
  @spec tap() :: :ok
  def tap do
    case Agent.start(fn -> nil end, name: @agent) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    case :telemetry.attach(@handler_id, [:ash_neo4j, :query], &__MODULE__.__handle_query__/4, nil) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  @doc """
  Stops capturing: detaches the telemetry handler and discards the stashed result.
  Idempotent.
  """
  @spec untap() :: :ok
  def untap do
    :telemetry.detach(@handler_id)
    if pid = Process.whereis(@agent), do: Agent.stop(pid)
    :ok
  end

  @doc """
  Renders the most recently captured query result as a flowchart string.

  Requires a prior `tap/0` and at least one successful query since. `opts` are
  passed to `flowchart/2`. Raises if nothing has been captured.
  """
  @spec last(keyword()) :: String.t()
  def last(opts \\ []) do
    case Process.whereis(@agent) && Agent.get(@agent, & &1) do
      %Response{} = response ->
        flowchart(response, opts)

      _ ->
        raise "AshNeo4j.Mermaid.last/1: nothing captured yet — call AshNeo4j.Mermaid.tap/0, then run a query"
    end
  end

  @doc false
  def __handle_query__(_event, _measurements, %{result: {:ok, %Response{} = response}}, _config) do
    # Only stash results that actually contain graph entities, so a plain scalar
    # (count/stat) query between graph queries doesn't clobber the last view.
    if graph_result?(response), do: Agent.update(@agent, fn _ -> response end)
    :ok
  end

  def __handle_query__(_event, _measurements, _metadata, _config), do: :ok

  # True if any result value is (or contains) a node, relationship or path.
  # Short-circuits on the first entity found.
  defp graph_result?(%Response{results: results}), do: Enum.any?(results, &has_entity?/1)

  defp has_entity?(%Node{}), do: true
  defp has_entity?(%Relationship{}), do: true
  defp has_entity?(%Bolty.Types.Path{}), do: true
  defp has_entity?(list) when is_list(list), do: Enum.any?(list, &has_entity?/1)

  defp has_entity?(map) when is_map(map) and not is_struct(map),
    do: Enum.any?(Map.values(map), &has_entity?/1)

  defp has_entity?(_other), do: false

  # --- collection -----------------------------------------------------------
  # Walk a result value, accumulating {nodes, edges} (each prepended; reversed
  # by the caller). Graph entities are collected; everything else is ignored.

  defp collect(%Node{} = node, {nodes, edges}), do: {[node | nodes], edges}

  defp collect(%Relationship{} = rel, {nodes, edges}), do: {nodes, [rel_edge(rel) | edges]}

  defp collect(%Bolty.Types.Path{} = path, {nodes, edges}) do
    nodes = Enum.reduce(path.nodes || [], nodes, fn n, acc -> [n | acc] end)
    edges = Enum.reduce(path_edges(path), edges, fn e, acc -> [e | acc] end)
    {nodes, edges}
  end

  defp collect(list, acc) when is_list(list), do: Enum.reduce(list, acc, &collect/2)

  defp collect(map, acc) when is_map(map) and not is_struct(map),
    do: Enum.reduce(Map.values(map), acc, &collect/2)

  defp collect(_scalar, acc), do: acc

  # --- paths ----------------------------------------------------------------
  # `Bolty.Types.Path.graph/1` rebuilds the walk but its UnboundRelationships
  # drop start/end (UnboundRelationship has no such fields, so struct/2 discards
  # them — bolty#55), so we reconstruct edge direction here straight from the
  # traversal sequence.
  #
  # `sequence` is [rel_index, node_index, rel_index, node_index, …]; the walk
  # starts at nodes[0]. A positive rel_index means the relationship is traversed
  # outgoing (current → next); a negative one (Neo4j sends 255 for -1) means
  # incoming (next → current). Relationship indices are 1-based into `relationships`.

  defp path_edges(%Bolty.Types.Path{nodes: nodes, relationships: rels, sequence: seq})
       when is_list(seq) and is_list(nodes) do
    seq
    |> Enum.chunk_every(2)
    |> Enum.reduce({List.first(nodes), []}, fn [rel_index, node_index], {current, acc} ->
      next = Enum.at(nodes, node_index)
      rel_index = if rel_index == 255, do: -1, else: rel_index

      {rel, from, to} =
        if rel_index > 0 do
          {Enum.at(rels, rel_index - 1), current, next}
        else
          {Enum.at(rels, -rel_index - 1), next, current}
        end

      {next, [{node_gid(from), node_gid(to), escape(to_string(rel.type))} | acc]}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp path_edges(_), do: []

  # --- rendering ------------------------------------------------------------

  defp node_line(%Node{} = node, opts), do: ~s(#{@indent}#{node_gid(node)}["#{node_text(node, opts)}"])
  defp node_line({:placeholder, gid}, _opts), do: ~s(#{@indent}#{gid}["?"])

  defp edge_line({from, to, ""}), do: "#{@indent}#{from} --> #{to}"
  defp edge_line({from, to, label}), do: "#{@indent}#{from} -->|#{label}| #{to}"

  defp node_text(%Node{labels: labels, properties: properties}, opts) do
    label_text = (labels || []) |> Enum.map_join(":", &escape(to_string(&1)))

    [label_text | property_lines(properties, opts)]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("<br/>")
  end

  defp property_lines(properties, opts) when is_map(properties) do
    case Keyword.get(opts, :properties, true) do
      false -> []
      keys when is_list(keys) -> Enum.flat_map(keys, &fetch_property(properties, &1))
      _ -> properties |> Map.to_list() |> Enum.map(&property_line/1)
    end
  end

  defp property_lines(_properties, _opts), do: []

  defp fetch_property(properties, key) do
    cond do
      Map.has_key?(properties, key) -> [property_line({key, Map.get(properties, key)})]
      Map.has_key?(properties, to_string(key)) -> [property_line({key, Map.get(properties, to_string(key))})]
      true -> []
    end
  end

  defp property_line({key, value}), do: "#{escape(to_string(key))}: #{escape(format_value(value))}"

  defp format_value(value) when is_binary(value), do: value
  defp format_value(value) when is_boolean(value), do: to_string(value)
  defp format_value(value) when is_number(value), do: to_string(value)
  defp format_value(nil), do: "null"
  defp format_value(value), do: inspect(value)

  # --- ids and escaping -----------------------------------------------------
  # Key nodes (and edge endpoints) by the integer graph id where present — it is
  # consistent across Node.id, Relationship.start/end and path nodes — falling
  # back to the string element id.

  defp node_gid(%Node{id: id}) when not is_nil(id), do: gid(id)
  defp node_gid(%Node{element_id: element_id}), do: gid(element_id)

  defp rel_edge(%Relationship{} = rel) do
    {endpoint_gid(rel.start, rel.start_node_element_id), endpoint_gid(rel.end, rel.end_node_element_id),
     escape(to_string(rel.type))}
  end

  defp endpoint_gid(id, _element_id) when not is_nil(id), do: gid(id)
  defp endpoint_gid(_id, element_id), do: gid(element_id)

  defp gid(id) when is_integer(id), do: "n#{id}"
  defp gid(id) when is_binary(id), do: "n" <> String.replace(id, ~r/[^A-Za-z0-9]/, "_")

  # Escape text destined for the inside of a `["…"]` label. `&` first, then the
  # angle brackets and quote, then turn newlines into Mermaid line breaks.
  defp escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("\n", "<br/>")
  end
end
