defmodule AshNeo4j.Ex4j.Helper do
  require Ash.Query
  use Ex4j.Cypher
  @doc """
  Queries neo4j using Ex4j to return list of Ex4j.Node
  """
  @spec match_nodes(module()) :: list(Ex4j.Node.t())
  def match_nodes(module) when is_atom(module) do
    Code.ensure_loaded(module)
    label = Module.split(module) |> List.last() |> String.to_existing_atom()
    match(module, as: label)
    |> return(label)
    |> run()
  end

  @doc """
  Queries neo4j using Ex4j to return list of Ex4j.Node, using Ash.Query
  """
  @spec match_nodes(module(), term()) :: list(Ex4j.Node.t())
  def match_nodes(module, ash_query) when is_atom(module) do
    IO.inspect(ash_query, label: "match_nodes ash_query")
    Code.ensure_loaded(module)
    label = Module.split(module) |> List.last() |> String.to_existing_atom()
    query =
      match(module, as: label)
      |> where_from_ash_filter(label, ash_query) |> IO.inspect(label: "match_nodes where_from_ash_filter")
      |> return(label)
    IO.inspect(cypher(query), label: "match_nodes cypher")
    query |> run()
  end

  @doc """
  Chains an Ex4j query with a where clause, derived from the Ash.Query.filter()
  filter: #Ash.Filter<title == "post2">
  resource_predicates_map: %{
    left: title,
    right: "post2",
    operator: :==,
    embedded?: false,
    __predicate__?: true,
    __operator__?: true
  }
  """
  def where_from_ash_filter(ex4j_query, label, ash_query) do
    if (ash_query.filter == nil) do
      ex4j_query
    else
      simple_filter = Ash.Filter.to_simple_filter(ash_query.filter)
      predicates = Map.get(simple_filter, :predicates, [])
      # TODO handle mulitple predicates
      first_predicate = Enum.at(predicates, 0)
      case first_predicate do
        %{left: attribute_name, operator: :==, right: value} ->
          property_name = AshNeo4j.DataLayer.Info.convert_to_property_name(ash_query.resource, attribute_name)
          #TODO enum is not correct here, need to update ex4j_query
          where(ex4j_query, label, "#{label}.#{property_name} = '#{value}'") |> IO.inspect(label: "AshNeo4j.DataLayer.where_from_ash_filter where")
        _ ->
          ex4j_query
          # TODO handle other predicates
      end
    end
  end
end
