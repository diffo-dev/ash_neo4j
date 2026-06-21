# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.DataLayer do
  @moduledoc """
  Ash DataLayer for Neo4j.

  ## Errors (#372)

  Every error the behaviour callbacks (`create`/`update`/`destroy`/`run_query`/…)
  return is a **typed struct** — never a bare string (a string becomes
  `Ash.Error.Unknown.UnknownError`: unclassified and only substring-matchable).
  Pick by meaning:

    * **Server/Bolt error** → `AshNeo4j.Error.Neo4j` (classifies by category).
    * **Deliberate refusal** ("can't push this down / won't render it") → the
      `AshNeo4j.Error.Unsupported*` / `Requires*` family (`class: :invalid`).
    * **The node/edge we expected to act on wasn't there** → reuse Ash's own:
      `Ash.Error.Changes.StaleRecord` (the record is gone / a guard no longer holds)
      or `Ash.Error.Invalid.Unavailable` (a preservation guard blocked a destroy).
    * **An internal invariant we couldn't satisfy** (unexpected input shape, a
      relationship/aggregate path that won't resolve) → `AshNeo4j.Error.Internal`
      (`class: :unknown`).

  Two standing rules: **reuse an Ash error before inventing an `AshNeo4j.Error.*`**,
  and **return, never raise**, from the behaviour path. Internal sentinels between
  helpers (e.g. `{:error, :nothing_deleted}` from `run_expecting_deletions/2`) are
  atoms, not strings, and are converted to a typed error before escaping. The
  contract is enforced by `test/error_contract_test.exs`.

  `Ash.Type` callbacks (cast/dump/load) are a separate contract — they follow Ash's
  type-error convention (message strings), not this one.
  """

  @behaviour Ash.DataLayer

  require Logger
  require AshGeo
  alias AshNeo4j.Resource.Info, as: ResourceInfo
  alias AshNeo4j.ResourceMapping
  alias AshNeo4j.EdgeDescriptor
  alias AshNeo4j.Neo4jHelper
  alias AshNeo4j.QueryHelper
  alias AshNeo4j.Cypher
  alias AshNeo4j.Cypher.Query, as: CypherQuery
  alias AshNeo4j.DataLayer.Cast
  alias AshNeo4j.DataLayer.Dump
  alias AshNeo4j.DataLayer.TypeClassifier
  alias AshNeo4j.Util

  @impl true
  def can?(_, :read), do: true
  def can?(_, :create), do: true
  def can?(_, :composite_primary_key), do: true
  def can?(_, :update), do: true
  # Advertise the "only-update-if" guard (#361) so Ash threads `changeset.filter`
  # into update/destroy — without this, `Ash.Changeset.filter/2` silently drops it.
  def can?(_, :changeset_filter), do: true
  # Atomic updates (#361): render `changeset.atomics` against the live node.
  def can?(_, {:atomic, :update}), do: true
  # Bulk atomic update (#361): apply the atomics/attributes to every node matching
  # the query in one statement (`Ash.bulk_update` :atomic strategy).
  def can?(_, :update_query), do: true
  # Bulk destroy (#361): delete every node matching the query in one statement,
  # skipping `guard`-protected nodes ("delete what is safe").
  def can?(_, :destroy_query), do: true
  # Ash gates the atomic bulk-destroy strategy on :update_query AND :expr_error
  # (#361). We don't render inline `error()` expressions — such an atomic refuses
  # cleanly via %UnsupportedAtomic{} (stance a) rather than mis-write. NB: with
  # full atomic support advertised, `manage_relationship` actions need
  # `require_atomic? false` (standard Ash 3), as they can't be done atomically.
  def can?(_, :expr_error), do: true
  def can?(_, :upsert), do: true
  def can?(_, :destroy), do: true
  def can?(_, :sort), do: true
  def can?(_, :filter), do: true
  def can?(_, :limit), do: true
  def can?(_, :offset), do: true
  def can?(_, :boolean_filter), do: true
  def can?(_, {:sort, _}), do: true
  def can?(_, {:join, _}), do: true
  def can?(_, {:lateral_join, _}), do: true
  def can?(_, {:filter_relationship, _}), do: true
  def can?(_, :nested_expressions), do: true

  # Operators with actual Cypher equivalents in convert_operator/1
  def can?(_, {:filter_expr, %Ash.Query.Operator.Eq{}}), do: true
  def can?(_, {:filter_expr, %Ash.Query.Operator.NotEq{}}), do: true
  def can?(_, {:filter_expr, %Ash.Query.Operator.In{}}), do: true
  def can?(_, {:filter_expr, %Ash.Query.Operator.LessThanOrEqual{}}), do: true
  def can?(_, {:filter_expr, %Ash.Query.Operator.LessThan{}}), do: true
  def can?(_, {:filter_expr, %Ash.Query.Operator.GreaterThan{}}), do: true
  def can?(_, {:filter_expr, %Ash.Query.Operator.GreaterThanOrEqual{}}), do: true
  def can?(_, {:filter_expr, %Ash.Query.Operator.IsNil{}}), do: true

  # contains — handled in predicates/2 via the %{name: :contains} branch
  def can?(_, {:filter_expr, %Ash.Query.Function.Contains{}}), do: true

  # spatial — st_contains(box, point) → point.withinBBox pushdown
  def can?(_, {:filter_expr, %AshNeo4j.Functions.StContains{}}), do: true

  # spatial — st_distance(point, point) → point.distance pushdown (in comparisons)
  def can?(_, {:filter_expr, %AshNeo4j.Functions.StDistance{}}), do: true

  # spatial — st_dwithin(point, point, ^km) → point.distance <= ^km pushdown
  def can?(_, {:filter_expr, %AshNeo4j.Functions.StDwithin{}}), do: true

  # spatial parity (in-memory eval) — st_within, st_intersects
  def can?(_, {:filter_expr, %AshNeo4j.Functions.StWithin{}}), do: true
  def can?(_, {:filter_expr, %AshNeo4j.Functions.StIntersects{}}), do: true

  # spatial — st_distance_in_meters: alias for st_distance, same pushdown
  def can?(_, {:filter_expr, %AshNeo4j.Functions.StDistanceInMeters{}}), do: true

  def can?(_, {:filter_expr, %AshNeo4j.Functions.VectorSimilarity{}}), do: true
  def can?(_, {:filter_expr, %AshNeo4j.Functions.VectorCosineDistance{}}), do: true

  # traversal — traverse(^chain, :field) reached-node filter → Cypher path pushdown (#321)
  def can?(_, {:filter_expr, %AshNeo4j.Functions.Traverse{}}), do: true

  # All other filter expressions are accepted so Ash can hydrate and then evaluate
  # them in-memory via filter_stream / RuntimeExpression. Cypher builder falls
  # back to TRUE for unrecognised predicates; filter_stream corrects the results.
  def can?(_, {:filter_expr, _}), do: true

  def can?(_, :transact), do: true
  def can?(_, :expression_calculation), do: true
  def can?(_, {:aggregate, kind}) when kind in [:count, :exists, :sum, :avg, :min, :max, :list, :first], do: true
  def can?(_, {:query_aggregate, kind}) when kind in [:count, :exists, :sum, :avg, :min, :max, :list, :first], do: true
  def can?(_, {:aggregate_relationship, _}), do: true
  # combination queries (#10)
  def can?(_, :combine), do: true
  def can?(_, {:combine, :base}), do: true
  def can?(_, {:combine, :union}), do: true
  def can?(_, {:combine, :union_all}), do: true
  def can?(_, {:combine, :intersect}), do: true
  def can?(_, {:combine, :except}), do: true

  def can?(_, _), do: false

  @impl true
  def functions(_resource) do
    [
      AshNeo4j.Functions.StClosestPoint,
      AshNeo4j.Functions.StContains,
      AshNeo4j.Functions.StDistance,
      AshNeo4j.Functions.StDistanceInMeters,
      AshNeo4j.Functions.StDwithin,
      AshNeo4j.Functions.StIntersects,
      AshNeo4j.Functions.StWithin,
      AshNeo4j.Functions.VectorSimilarity,
      AshNeo4j.Functions.VectorCosineDistance,
      AshNeo4j.Functions.Traverse
    ]
  end

  @neo4j %Spark.Dsl.Section{
    name: :neo4j,
    examples: [
      """
      neo4j do
        label :Comment
        relate [{:post, :BELONGS_TO, :outgoing, :Post}]
      end
      """
    ],
    schema: [
      label: [
        type: :atom,
        doc: "Optional node label",
        required: false
      ],
      relate: [
        type: {:list, {:tuple, [:atom, :atom, :atom, :atom]}},
        doc:
          "Optional list of relationships, as tuples of {relationship_name, edge_label, edge_direction, destination_label}",
        required: false,
        default: []
      ],
      guard: [
        type: {:list, {:tuple, [:atom, :atom, :atom]}},
        doc: "Optional list of node relationships, as tuples of {edge_label, edge_direction, destination_label}",
        required: false,
        default: []
      ],
      skip: [
        type: {:list, :atom},
        doc: "Optional list of attributes not to be stored directly as node properties",
        required: false,
        default: []
      ]
    ]
  }

  @impl true
  def limit(query, offset, _), do: {:ok, %{query | limit: offset}}

  @impl true
  def offset(query, offset, _), do: {:ok, %{query | offset: offset}}

  @impl true
  def filter(query, filter, _resource) do
    {:ok, %{query | filter: filter}}
  end

  @impl true
  def sort(query, sort, _resource) do
    deduplicated = Enum.uniq_by(sort, fn {field, _order} -> field end)
    {:ok, %{query | sort: deduplicated}}
  end

  @doc false
  def store_opt(attributes) do
    if Enum.all?(attributes, &is_atom/1) do
      {:ok, attributes}
    else
      {:error, internal("expected all attribute names to be atoms, got #{inspect(attributes)}")}
    end
  end

  @sections [@neo4j]

  use Spark.Dsl.Extension,
    sections: @sections,
    persisters: [
      AshNeo4j.Persisters.PersistLabels,
      AshNeo4j.Persisters.PersistTranslations,
      AshNeo4j.Persisters.PersistRelationshipAttributes,
      AshNeo4j.Persisters.PersistRelate,
      AshNeo4j.Persisters.PersistMapping
    ],
    verifiers: [
      AshNeo4j.Verifiers.VerifyLabelsPascalCase,
      AshNeo4j.Verifiers.VerifyRelate,
      AshNeo4j.Verifiers.VerifyGuard,
      AshNeo4j.Verifiers.VerifyPropertiesCamelCase,
      AshNeo4j.Verifiers.VerifyEnrichable,
      AshNeo4j.Verifiers.VerifyAttributeType,
      AshNeo4j.Verifiers.VerifyIdentities
    ]

  defmodule Query do
    @moduledoc false
    defstruct [
      :resource,
      :sort,
      :filter,
      :limit,
      :offset,
      :domain,
      aggregates: %{},
      calculations: %{},
      combination_of: []
    ]
  end

  @impl true
  @spec run_query(any(), atom()) :: {:error, any()} | {:ok, any()}
  def run_query(query, resource) do
    Logger.debug("AshNeo4j.DataLayer: run_query(#{inspect(query)}, #{inspect(resource)})")

    result =
      case QueryHelper.query_nodes(query) do
        {:error, error} ->
          {:error, error}

        {:ok, []} ->
          {:ok, []}

        {:ok, groups} ->
          all_results =
            convert_groups_to_resources(query, groups)
            |> Enum.to_list()

          case Enum.find(all_results, &match?({:error, _}, &1)) do
            nil ->
              records =
                Enum.map(all_results, fn
                  {:ok, r} -> r
                  r -> r
                end)

              aggregates = Map.values(Map.get(query, :aggregates) || %{})
              calculations = Map.values(Map.get(query, :calculations) || %{})

              with {:ok, records} <- apply_calculations_to_records(records, calculations, resource),
                   records <- filter_matches(records, drop_pushdown_only(query.filter), query.domain),
                   {:ok, records} <- apply_aggregates_to_records(records, aggregates, resource) do
                {:ok, apply_calculation_sort(records, query.sort, query.domain)}
              end

            {:error, reason} ->
              {:error, reason}
          end
      end

    Logger.debug("AshNeo4j.DataLayer: run_query result #{inspect(result)}")

    result
  end

  @impl true
  def add_aggregates(query, aggregates, _resource) do
    {:ok, %{query | aggregates: Map.merge(query.aggregates || %{}, Map.new(aggregates, &{&1.name, &1}))}}
  end

  @impl true
  def add_calculation(query, calculation, expression, _resource) do
    calcs = Map.get(query, :calculations) || %{}
    {:ok, %{query | calculations: Map.put(calcs, calculation.name, {calculation, expression})}}
  end

  @impl true
  def run_aggregate_query(data_layer_query, aggregates, resource) do
    mapping = ResourceInfo.mapping(resource)
    pk_field = hd(Ash.Resource.Info.primary_key(resource))
    neo4j_pk = Keyword.get(mapping.properties, pk_field, pk_field)

    case run_query(data_layer_query, resource) do
      {:ok, records} ->
        ids = Enum.map(records, &Map.get(&1, pk_field))

        Enum.reduce_while(aggregates, {:ok, %{}}, fn aggregate, {:ok, acc} ->
          case run_aggregate_for_ids(mapping, neo4j_pk, ids, aggregate, :total) do
            {:ok, value} -> {:cont, {:ok, Map.put(acc, aggregate.name, value)}}
            {:error, e} -> {:halt, {:error, e}}
          end
        end)

      {:error, e} ->
        {:error, e}
    end
  end

  @impl true
  @spec create(atom() | map(), any()) ::
          {:error, <<_::64, _::_*8>> | %{:__exception__ => true, :__struct__ => atom(), optional(atom()) => any()}}
          | {:ok, any()}
  def create(resource, changeset) do
    Logger.debug("AshNeo4j.DataLayer: create(#{inspect(resource)}, #{inspect(changeset)})")

    mapping = ResourceInfo.mapping(resource)
    primary_keys = Ash.Resource.Info.primary_key(mapping.module)
    id_attributes = Map.take(changeset.attributes, primary_keys)

    result =
      with :ok <- validate_writable_geo(mapping, changeset.attributes) do
        if Enum.empty?(id_attributes) do
          {:error, internal("no values supplied for primary keys #{inspect(primary_keys)}")}
        else
          create_from_attributes(mapping, changeset.attributes)
        end
      end
      |> map_identity_conflict(resource, changeset)

    Logger.debug("AshNeo4j.DataLayer: create result #{inspect(result)}")

    result
  end

  # A Neo4j uniqueness-constraint violation (#20) means the resource's `identity`
  # was breached. Surface it as Ash's own identity-conflict error — one
  # `InvalidAttribute` ("has already been taken") per attribute of the violated
  # identity — so it reads in Ash terms (resource + attributes), not as a raw graph
  # error. Through the driver the violation's code is reliable
  # (`ConstraintValidationFailed`) but its message is generic, so the identity is
  # found from the changeset: the one whose keys are all set (so could have
  # collided). Exactly one such identity ⇒ map it; none or ambiguous ⇒ fall back to
  # the raw error rather than guess.
  defp map_identity_conflict({:error, %AshNeo4j.Error.Neo4j{category: :constraint}} = error, resource, changeset) do
    case conflicting_identity(resource, changeset.attributes) do
      %{keys: keys} ->
        {:error, Enum.map(keys, &Ash.Error.Changes.InvalidAttribute.exception(field: &1, message: "has already been taken"))}

      nil ->
        error
    end
  end

  defp map_identity_conflict(result, _resource, _changeset), do: result

  defp conflicting_identity(resource, attributes) do
    case Enum.filter(Ash.Resource.Info.identities(resource), fn identity ->
           Enum.all?(identity.keys, &(Map.get(attributes, &1) != nil))
         end) do
      [identity] -> identity
      _ -> nil
    end
  end

  @impl true
  def upsert(resource, changeset, keys) do
    Logger.debug("AshNeo4j.DataLayer: upsert(#{inspect(resource)}, #{inspect(changeset)}, #{inspect(keys)})")

    mapping = ResourceInfo.mapping(resource)

    result =
      if mergeable_upsert?(changeset) do
        merge_upsert(resource, changeset, keys, mapping)
      else
        # Atomics, managed relationships or an upsert condition can't be expressed
        # in a single MERGE — keep the read-then-write path for those.
        legacy_upsert(resource, changeset, keys, mapping)
      end

    Logger.debug("AshNeo4j.DataLayer: upsert result #{inspect(result)}")

    result
  end

  # Only a plain attribute upsert can be a single atomic MERGE (#379).
  defp mergeable_upsert?(changeset) do
    changeset.atomics in [nil, []] and
      (changeset.relationships == nil or changeset.relationships == %{}) and
      is_nil(changeset.filter)
  end

  # Atomic, race-free, single-statement upsert (#379): MERGE on the upsert
  # identity's properties, ON CREATE SET the rest of the node, ON MATCH SET the
  # `set_on_upsert` fields. Backed by the identity's uniqueness constraint (#20).
  defp merge_upsert(resource, changeset, keys, mapping) do
    key_values = Map.new(keys, fn key -> {key, Ash.Changeset.get_attribute(changeset, key)} end)

    if Enum.any?(Map.values(key_values), &is_nil/1) do
      # No identity to merge on — a plain create.
      create(resource, changeset)
    else
      merge_props = dump_properties(mapping, key_values)
      create_props = dump_properties(mapping, Map.drop(changeset.attributes, keys))
      match_props = dump_properties(mapping, Map.new(Ash.Changeset.set_on_upsert(changeset, keys)))

      case Neo4jHelper.upsert_node(mapping.label_pair, merge_props, create_props, match_props) do
        {:ok, %Bolty.Response{results: [node_map | _]}} ->
          convert_node_to_resource(resource, Map.get(node_map, "n"))

        {:ok, %Bolty.Response{results: []}} ->
          {:error, internal("upsert affected no node")}

        {:error, error} ->
          {:error, AshNeo4j.Error.Neo4j.from_bolt(error)}
      end
      |> map_identity_conflict(resource, changeset)
    end
  end

  defp legacy_upsert(resource, changeset, keys, mapping) do
    id_properties = id_properties(mapping, changeset.attributes)

    if Enum.any?(Map.values(id_properties), &is_nil(&1)) do
      create(resource, changeset)
    else
      key_filters =
        Enum.map(keys, fn key ->
          {key,
           Ash.Changeset.get_attribute(changeset, key) || Map.get(changeset.params, key) ||
             Map.get(changeset.params, to_string(key))}
        end)

      query = Ash.Query.do_filter(resource, and: [key_filters])

      resource
      |> resource_to_query(changeset.domain)
      |> Map.put(:filter, query.filter)
      |> Map.put(:tenant, changeset.tenant)
      |> run_query(resource)
      |> case do
        {:ok, []} ->
          create(resource, changeset)

        {:ok, [result]} ->
          to_set = Ash.Changeset.set_on_upsert(changeset, keys)

          changeset =
            changeset
            |> Map.put(:attributes, %{})
            |> Map.put(:data, result)
            |> Ash.Changeset.force_change_attributes(to_set)

          update(resource, changeset)

        {:ok, _} ->
          {:error, internal("multiple records match the upsert keys")}
      end
    end
  end

  @impl true
  def update(resource, changeset) do
    Logger.debug("AshNeo4j.DataLayer: update(#{inspect(resource)}, #{inspect(changeset)})")

    mapping = ResourceInfo.mapping(resource)

    with :ok <- validate_writable_geo(mapping, changeset.attributes) do
      do_update(resource, changeset, mapping)
    end
  end

  defp do_update(resource, changeset, %ResourceMapping{} = mapping) do
    # Honour the `changeset.filter` "only-update-if" guard and render
    # `changeset.atomics` against the live node (#361). Refuse anything we can't
    # render in full rather than write unguarded / mis-write (stance a).
    with {:ok, guard_conditions} <- QueryHelper.guard_conditions(mapping, changeset.filter),
         {:ok, atomic_sets} <- QueryHelper.render_atomic_sets(resource, mapping, changeset.atomics || []) do
      do_update(resource, changeset, mapping, guard_conditions, atomic_sets)
    end
  end

  # The optimistic-lock failure raised when a `changeset.filter`-guarded write
  # matches zero rows — the live node no longer satisfies the guard (#361/#368).
  defp stale_record(resource, changeset) do
    Ash.Error.Changes.StaleRecord.exception(resource: resource, filter: changeset.filter)
  end

  # An internal invariant the data layer couldn't satisfy (#372) — typed,
  # matchable, classified `:unknown`, in place of a bare-string error.
  defp internal(detail), do: AshNeo4j.Error.Internal.exception(detail: detail)

  defp do_update(resource, changeset, %ResourceMapping{} = mapping, guard_conditions, atomic_sets) do
    subject_id = id_properties(mapping, changeset.data)
    subject_label = mapping.label_pair

    update_properties = dump_properties(mapping, changeset.attributes)

    remove_property_names = stale_property_names(mapping, update_properties, changeset)

    guarded? = guard_conditions != []
    {atomic_exprs, _atomic_params} = atomic_sets

    property_update_result =
      if !Enum.empty?(update_properties) or !Enum.empty?(remove_property_names) or guarded? or
           atomic_exprs != [] do
        case subject_label
             |> Neo4jHelper.update_node(subject_id, update_properties, remove_property_names,
               guard: guard_conditions,
               atomics: atomic_sets
             ) do
          # No row matched: a present guard ⇒ the predicate no longer holds;
          # otherwise the id itself didn't match. Either way the record we meant to
          # update is gone — StaleRecord (#372).
          {:ok, %Bolty.Response{results: []}} ->
            {:error, stale_record(resource, changeset)}

          {:ok, %Bolty.Response{results: [node_map | _]}} ->
            node = Map.get(node_map, "n")
            convert_node_to_resource(resource, node)

          {:error, error} ->
            {:error, AshNeo4j.Error.Neo4j.from_bolt(error)}
        end
      end

    relationship_update_result =
      if accessing_from = Map.get(changeset.context, :accessing_from) do
        object_resource = Map.get(accessing_from, :source)
        object_label = ResourceInfo.label(object_resource)
        object_relationship_name = Map.get(accessing_from, :name)
        object_node_relationship = ResourceInfo.node_relationship(object_resource, object_relationship_name)

        if Map.get(accessing_from, :unrelating?) do
          object_id =
            relationship_properties(resource, object_resource, changeset.data, object_relationship_name)

          case map_size(object_id) do
            0 ->
              {:error, internal("couldn't resolve the node to unrelate from #{inspect(resource)}.#{object_relationship_name}")}

            _ ->
              {_relationship_name, edge_label, object_to_subject_direction, _destination_label} =
                object_node_relationship

              case Neo4jHelper.unrelate_nodes(
                     subject_label,
                     subject_id,
                     object_label,
                     object_id,
                     edge_label,
                     Util.reverse(object_to_subject_direction),
                     guard_conditions
                   ) do
                {:ok, %Bolty.Response{results: []}} ->
                  {:error, stale_record(resource, changeset)}

                {:ok, %Bolty.Response{results: [node_map | _]}} ->
                  node = Map.get(node_map, "s")
                  convert_node_to_resource(resource, node)

                {:error, error} ->
                  {:error, error}
              end
          end
        else
          object_id = relationship_properties(resource, object_resource, changeset.attributes, object_relationship_name)

          case map_size(object_id) do
            0 ->
              # Empty object id ⇒ the inverse-relationship resolution failed. If both sides are
              # `has_many` over one edge, that's a back-to-back-has_many m2m (#127) —
              # fail fast with guidance toward a joiner node rather than a bare string.
              if back_to_back_has_many?(resource, object_resource, object_relationship_name) do
                {:error,
                 AshNeo4j.Error.UnsupportedManyToMany.exception(
                   resource: object_resource,
                   related: resource,
                   relationship: object_relationship_name
                 )}
              else
                {:error, internal("couldn't resolve the node to relate from #{inspect(resource)}.#{object_relationship_name}")}
              end

            _ ->
              {_relationship_name, edge_label, object_to_subject_direction, _object_label} = object_node_relationship

              case Neo4jHelper.relate_nodes(
                     subject_label,
                     subject_id,
                     object_label,
                     object_id,
                     edge_label,
                     Util.reverse(object_to_subject_direction),
                     guard: guard_conditions
                   ) do
                {:ok, %Bolty.Response{results: []}} ->
                  {:error, stale_record(resource, changeset)}

                {:ok, %Bolty.Response{results: [node_map | _]}} ->
                  node = Map.get(node_map, "s")
                  convert_node_to_resource(resource, node)

                {:error, error} ->
                  {:error, error}
              end
          end
        end
      else
        if changeset.relationships do
          Enum.reduce_while(changeset.relationships, nil, fn {relationship_name, relationship_change}, _acc ->
            subject_edge = Enum.find(mapping.edges, &(&1.relationship == relationship_name))

            subject_relationship =
              Ash.Resource.Info.relationship(resource, relationship_name)

            object_resource = subject_relationship.destination
            object_label = ResourceInfo.label(object_resource)

            {arguments, options} = hd(relationship_change)
            type = Keyword.get(options, :type)

            cond do
              arguments == [] or type == :remove ->
                subject_source_attribute = subject_relationship.source_attribute
                subject_destination_attribute = subject_relationship.destination_attribute

                object_property_name =
                  ResourceInfo.convert_to_property_name(object_resource, subject_destination_attribute)

                object_property_value = Map.get(changeset.data, subject_source_attribute)
                object_id = %{object_property_name => object_property_value}

                case map_size(object_id) do
                  0 ->
                    {:halt, {:error, internal("couldn't resolve the node to unrelate for #{inspect(resource)}.#{relationship_name}")}}

                  _ ->
                    case Neo4jHelper.unrelate_nodes(
                           subject_label,
                           subject_id,
                           object_label,
                           object_id,
                           subject_edge.label,
                           subject_edge.direction,
                           guard_conditions
                         ) do
                      {:ok, %Bolty.Response{results: []}} ->
                        {:halt, {:error, stale_record(resource, changeset)}}

                      {:ok, %Bolty.Response{results: [node_map | _]}} ->
                        node = Map.get(node_map, "s")

                        case convert_node_to_resource(resource, node) do
                          {:ok, resource} -> {:cont, {:ok, resource}}
                          {:error, reason} -> {:halt, {:error, reason}}
                        end

                      {:error, error} ->
                        {:halt, {:error, error}}
                    end
                end

              true ->
                arg_relate_result =
                  Enum.reduce_while(arguments, nil, fn argument, _acc ->
                    object_id = ResourceInfo.convert_to_properties(object_resource, argument)

                    case map_size(object_id) do
                      0 ->
                        {:halt, {:error, internal("couldn't resolve the node to relate for #{inspect(resource)}.#{relationship_name} from argument #{inspect(argument)}")}}

                      _ ->
                        subject_exclusive? = ResourceInfo.source_exclusive?(resource, relationship_name)
                        object_exclusive? = ResourceInfo.destination_exclusive?(resource, relationship_name)

                        case Neo4jHelper.relate_nodes(
                               subject_label,
                               subject_id,
                               object_label,
                               object_id,
                               subject_edge.label,
                               subject_edge.direction,
                               exclusive: {subject_exclusive?, object_exclusive?},
                               guard: guard_conditions
                             ) do
                          # Zero rows: with a guard (#368) the live source no longer
                          # satisfies it; without one the subject/dest didn't match.
                          # Either way the record is gone ⇒ StaleRecord (#372).
                          {:ok, %Bolty.Response{results: []}} ->
                            {:halt, {:error, stale_record(resource, changeset)}}

                          {:ok, %Bolty.Response{results: [node_map | _]}} ->
                            node = Map.get(node_map, "s")

                            case convert_node_to_resource(resource, node) do
                              {:ok, resource} -> {:cont, {:ok, resource}}
                              {:error, reason} -> {:halt, {:error, reason}}
                            end

                          {:error, error} ->
                            {:halt, {:error, error}}
                        end
                    end
                  end)

                case arg_relate_result do
                  {:error, _} ->
                    {:halt, arg_relate_result}

                  {:ok, _} ->
                    {:cont, arg_relate_result}
                end
            end
          end)
        else
          {:error, internal("update changeset not handled (no attributes, atomics or relationships to apply)")}
        end
      end

    result = relationship_update_result || property_update_result

    Logger.debug("AshNeo4j.DataLayer: update result #{inspect(result)}")

    result
  end

  @impl true
  def update_query(query, changeset, resource, opts) do
    Logger.debug("AshNeo4j.DataLayer: update_query(#{inspect(query)}, #{inspect(changeset)}, #{inspect(resource)})")

    mapping = ResourceInfo.mapping(resource)

    cond do
      # Relationship management (manage_relationship) is routed here as an atomic
      # set of the relationship attribute, but in the graph that relationship is an
      # *edge*, not a stored property. Hand it to the per-record path, which creates
      # the edge (and renders the atomic) (#361).
      Map.has_key?(changeset.context, :accessing_from) ->
        single_update_query_result(resource, changeset, mapping, opts)

      true ->
        bulk_update_query(query, changeset, resource, mapping, opts)
    end
  end

  defp single_update_query_result(resource, changeset, mapping, opts) do
    # Ash atomic-ises the relationship attribute, so the edge key arrives in
    # `atomics` — as a literal (belongs_to) or a guard expression like
    # `if is_distinct_from(new, current), do: new, else: current` (has_one). The
    # per-record relationship path reads that attribute from `attributes`, so
    # evaluate each atomic against the live record and fold it back, then delegate
    # (creates the edge).
    with {:ok, changeset} <- fold_atomics_to_attributes(resource, changeset),
         {:ok, record} <- do_update(resource, changeset, mapping) do
      if Map.get(opts, :return_records?), do: {:ok, [record]}, else: :ok
    end
  end

  defp fold_atomics_to_attributes(resource, changeset) do
    Enum.reduce_while(changeset.atomics, {:ok, changeset.attributes}, fn {field, expr}, {:ok, acc} ->
      case Ash.Expr.eval(expr, record: changeset.data, resource: resource) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, field, value)}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, attributes} -> {:ok, %{changeset | attributes: attributes, atomics: []}}
      error -> error
    end
  end

  defp bulk_update_query(query, changeset, resource, mapping, opts) do
    # `query.filter` already folds in any changeset (optimistic-lock) filter via
    # Ash's add_changeset_filters/2. Stance (a): the scope must push down in full —
    # we can't post-filter a bulk SET in Elixir — else refuse (#361).
    with {:ok, conditions} <- QueryHelper.guard_conditions(mapping, query.filter),
         {:ok, atomic_sets} <- QueryHelper.render_atomic_sets(resource, mapping, changeset.atomics || []) do
      set_props = dump_properties(mapping, changeset.attributes)

      case Neo4jHelper.update_node(mapping.label_pair, %{}, set_props, [],
             guard: conditions,
             atomics: atomic_sets
           ) do
        {:ok, %Bolty.Response{results: results}} ->
          bulk_update_result(resource, results, opts)

        {:error, error} ->
          {:error, AshNeo4j.Error.Neo4j.from_bolt(error)}
      end
    end
  end

  # `:ok` when records aren't requested, else `{:ok, records}` — short-circuiting
  # on the first node that fails to convert.
  defp bulk_update_result(resource, results, opts) do
    if Map.get(opts, :return_records?) do
      converted = Enum.map(results, &convert_node_to_resource(resource, Map.get(&1, "n")))

      case Enum.find(converted, &match?({:error, _}, &1)) do
        nil -> {:ok, Enum.map(converted, fn {:ok, record} -> record end)}
        {:error, _} = error -> error
      end
    else
      :ok
    end
  end

  @impl true
  def destroy_query(query, changeset, resource, opts) do
    Logger.debug("AshNeo4j.DataLayer: destroy_query(#{inspect(query)}, #{inspect(changeset)}, #{inspect(resource)})")

    mapping = ResourceInfo.mapping(resource)

    cond do
      # Relationship-context destroy — hand to the per-record path (which enforces
      # the guard as an error, the right semantics for a targeted destroy) (#361).
      Map.has_key?(changeset.context, :accessing_from) ->
        single_destroy_query_result(resource, changeset, opts)

      true ->
        bulk_destroy_query(query, resource, mapping, opts)
    end
  end

  defp single_destroy_query_result(resource, changeset, opts) do
    case destroy(resource, changeset) do
      :ok -> if Map.get(opts, :return_records?), do: {:ok, [changeset.data]}, else: :ok
      {:error, _} = error -> error
    end
  end

  defp bulk_destroy_query(query, resource, mapping, opts) do
    # Stance (a): scope must push down in full (no Elixir post-filter on a bulk
    # delete), else refuse. `guard`-protected nodes are skipped, not deleted.
    with {:ok, conditions} <- QueryHelper.guard_conditions(mapping, query.filter) do
      return? = Map.get(opts, :return_records?, false)
      guards = ResourceInfo.preserve_node_relationships(resource)

      case Neo4jHelper.bulk_detach_delete(mapping.label_pair, conditions, guards, return?) do
        {:ok, %Bolty.Response{results: results}} ->
          if return?, do: convert_deleted_nodes(resource, results), else: :ok

        {:error, error} ->
          {:error, AshNeo4j.Error.Neo4j.from_bolt(error)}
      end
    end
  end

  # Rebuild records from the pre-delete node data captured in the `WITH`.
  defp convert_deleted_nodes(resource, results) do
    converted =
      Enum.map(results, fn row ->
        node = %Bolty.Types.Node{
          id: Map.get(row, "nid"),
          properties: Map.get(row, "props"),
          labels: Map.get(row, "labels")
        }

        convert_node_to_resource(resource, node)
      end)

    case Enum.find(converted, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(converted, fn {:ok, record} -> record end)}
      {:error, _} = error -> error
    end
  end

  @impl true
  def destroy(resource, changeset) do
    Logger.debug("AshNeo4j.DataLayer: destroy(#{inspect(resource)}, #{inspect(changeset)})")

    mapping = ResourceInfo.mapping(resource)

    # Honour a `changeset.filter` "only-destroy-if" guard (optimistic lock, #361):
    # render it (refuse an un-pushable filter, stance a) and route. `{:ok, []}` is
    # the unfiltered case.
    with {:ok, conditions} <- QueryHelper.guard_conditions(mapping, changeset.filter) do
      destroy_with_conditions(resource, mapping, conditions, changeset)
    end
  end

  defp destroy_with_conditions(resource, %ResourceMapping{} = mapping, [], changeset) do
    destroy_node(resource, mapping.label_pair, id_properties(mapping, changeset.data))
  end

  defp destroy_with_conditions(resource, %ResourceMapping{} = mapping, conditions, changeset) do
    label = mapping.label_pair
    id_properties = id_properties(mapping, changeset.data)
    guards = ResourceInfo.preserve_node_relationships(resource)

    case Neo4jHelper.delete_node_filtered(label, id_properties, conditions, guards) do
      {:ok, _} ->
        :ok

      # Nothing deleted: if the node still matches the filter it was held back by a
      # guard (Unavailable); otherwise the optimistic lock didn't hold (StaleRecord).
      {:error, :nothing_deleted} ->
        case Neo4jHelper.node_matching(label, id_properties, conditions) do
          {:ok, %Bolty.Response{results: [_ | _]}} ->
            {:error, unavailable_guarded(resource)}

          _ ->
            {:error, stale_record(resource, changeset)}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp unavailable_guarded(resource) do
    Ash.Error.Invalid.Unavailable.exception(
      resource: resource,
      source: AshNeo4j.DataLayer,
      reason: "guarded relationships prevent deletion"
    )
  end

  defp destroy_node(resource, label, id_properties) do
    result =
      case Neo4jHelper.safe_delete_nodes(label, id_properties, ResourceInfo.preserve_node_relationships(resource)) do
        {:ok, _} ->
          :ok

        {:error, :nothing_deleted} ->
          {:error, unavailable_guarded(resource)}

        {:error, error} ->
          {:error, error}
      end

    Logger.debug("AshNeo4j.DataLayer: delete result #{inspect(result)}")

    result
  end

  @impl true
  def resource_to_query(resource, domain) do
    %Query{resource: resource, domain: domain}
  end

  @impl true
  def combination_of(combinations, resource, domain) do
    {:ok, %Query{resource: resource, domain: domain, combination_of: combinations}}
  end

  @impl true
  def transaction(resource, fun, _timeout, _) do
    label = ResourceInfo.label(resource)

    if AshNeo4j.Sandbox.active?() do
      prev = Process.get(:ash_neo4j_in_sandbox_tx, false)
      Process.put(:ash_neo4j_in_sandbox_tx, true)
      Process.put({:neo4j_in_transaction, label}, true)

      try do
        case fun.() do
          {:error, error} -> {:error, error}
          result -> {:ok, result}
        end
      catch
        {{:neo4j_rollback, _}, value} -> {:error, value}
      after
        Process.put(:ash_neo4j_in_sandbox_tx, prev)
        Process.delete({:neo4j_in_transaction, label})
      end
    else
      Bolty.transaction(AshNeo4j.BoltyHelper.current_pool(), fn conn ->
        stack = Process.get(:ash_neo4j_tx_stack, [])
        Process.put(:ash_neo4j_tx_stack, [conn | stack])
        Process.put({:neo4j_in_transaction, label}, true)

        try do
          case fun.() do
            {:error, error} -> Bolty.rollback(conn, error)
            result -> result
          end
        catch
          {{:neo4j_rollback, _}, value} -> Bolty.rollback(conn, value)
        after
          Process.put(:ash_neo4j_tx_stack, stack)
          Process.delete({:neo4j_in_transaction, label})
        end
      end)
    end
  end

  @impl true
  def rollback(resource, error) do
    throw({{:neo4j_rollback, ResourceInfo.label(resource)}, error})
  end

  @impl true
  def in_transaction?(_resource) do
    Process.get(:ash_neo4j_tx_stack, []) != [] or
      Process.get(:ash_neo4j_in_sandbox_tx, false)
  end

  defp filter_matches(records, nil, _domain), do: records

  defp filter_matches(records, filter, domain) do
    {:ok, records} = Ash.Filter.Runtime.filter_matches(domain, records, filter)
    records
  end

  # **Pushdown-only** expressions (#321 `traverse`, and future engine ops) are
  # graph operations applied *exactly* by the Cypher pushdown and have no
  # in-memory value. The residual filter for the in-memory correctness pass is
  # therefore the original filter with every sub-expression containing a
  # pushdown-only function replaced by `true` — leaving all ordinary predicates
  # (which the pushdown may over-return on) intact for re-filtering. A function
  # opts in via `ash_neo4j_pushdown_only?/0`. (Per-predicate residual tracking —
  # re-applying only what wasn't pushed — is the cleaner end-state, see #327.)
  defp drop_pushdown_only(nil), do: nil

  defp drop_pushdown_only(%Ash.Filter{expression: expression} = filter),
    do: %{filter | expression: drop_pushdown_only_expr(expression)}

  defp drop_pushdown_only(filter), do: drop_pushdown_only_expr(filter)

  defp drop_pushdown_only_expr(%Ash.Query.BooleanExpression{left: left, right: right} = boolean) do
    %{boolean | left: drop_pushdown_only_expr(left), right: drop_pushdown_only_expr(right)}
  end

  defp drop_pushdown_only_expr(%Ash.Query.Not{expression: expression} = negation) do
    %{negation | expression: drop_pushdown_only_expr(expression)}
  end

  # A `fragment(...)` that reached the data layer was pushed down (we refuse the
  # ones we can't push) — and it can't be evaluated in-memory anyway — so drop it
  # from the in-memory residual (#33).
  defp drop_pushdown_only_expr(%Ash.Query.Function.Fragment{}), do: true

  defp drop_pushdown_only_expr(expression) do
    if contains_pushdown_only?(expression), do: true, else: expression
  end

  defp contains_pushdown_only?(%module{} = struct) do
    pushdown_only_function?(module) or
      (struct |> Map.from_struct() |> Map.values() |> Enum.any?(&contains_pushdown_only?/1))
  end

  defp contains_pushdown_only?(map) when is_map(map), do: map |> Map.values() |> Enum.any?(&contains_pushdown_only?/1)
  defp contains_pushdown_only?(list) when is_list(list), do: Enum.any?(list, &contains_pushdown_only?/1)
  defp contains_pushdown_only?(_), do: false

  defp pushdown_only_function?(module) do
    function_exported?(module, :ash_neo4j_pushdown_only?, 0) and module.ash_neo4j_pushdown_only?()
  end

  # Reads the on-disk property value for an attribute, handling the geo
  # path specially: for `:geo` classified attributes the canonical lives
  # at `<attr>.json` as an RFC 7946 GeoJSON STRING, which we decode here
  # so Cast just sees the resulting %Geo.*{} struct and dispatches it
  # through standard `:ash` (AshGeo's identity cast_stored).
  defp read_attribute_property(resource, resource_field, node_field, properties) do
    base = to_string(node_field)

    case Ash.Resource.Info.attribute(resource, resource_field) do
      %{type: type} ->
        attribute_type = Ash.Type.get_type!(type)

        case TypeClassifier.classify(attribute_type) do
          {:ok, :geo, _} ->
            case Map.get(properties, "#{base}.json") do
              nil -> nil
              json when is_binary(json) -> AshNeo4j.GeoJson.decode!(json)
            end

          _ ->
            Map.get(properties, base)
        end

      _ ->
        Map.get(properties, base)
    end
  end

  defp consolidate_groups(groups) when is_list(groups) do
    Enum.reduce(groups, [], fn group, acc ->
      s = Map.get(group, "s")
      tuple_count = Integer.floor_div(Enum.count(group), 2)

      tuples =
        Enum.reduce(0..(tuple_count - 1)//1, [], fn tuple, acc ->
          r = Map.get(group, "r#{tuple}") || Map.get(group, "r")
          d = Map.get(group, "d#{tuple}") || Map.get(group, "d")

          cond do
            r != nil && d != nil ->
              [{r, d} | acc]

            true ->
              acc
          end
        end)

      cond do
        [] == acc ->
          [{s, tuples}]

        [previous | tail] = acc ->
          cond do
            Map.get(s, :id) == elem(previous, 0).id ->
              cond do
                tuples == [] ->
                  acc

                true ->
                  [{s, tuples ++ elem(previous, 1)} | tail]
              end

            true ->
              [{s, tuples} | acc]
          end
      end
    end)
    |> Enum.into(
      [],
      fn group ->
        {source, related} = group
        {source, Enum.reverse(related)}
      end
    )
    |> Enum.reverse()
  end

  defp convert_groups_to_resources(query, groups) when is_struct(query, Query) and is_list(groups) do
    mapping = ResourceInfo.mapping(query.resource)

    consolidate_groups(groups)
    |> Stream.map(&convert_to_resource(query, mapping, &1))
  end

  defp convert_to_resource(query, %ResourceMapping{} = mapping, consolidated_group)
       when is_struct(query, Query) and is_tuple(consolidated_group) do
    source_node = elem(consolidated_group, 0)
    related = elem(consolidated_group, 1)

    enrichments =
      Enum.reduce(related, [], &enrichments(mapping, &2, &1))
      |> consolidate_enrichments()

    convert_node_to_resource(mapping, source_node, enrichments)
  end

  defp consolidate_enrichments(enrichments) when is_list(enrichments) do
    Enum.reduce(enrichments, [], fn enrichment, acc ->
      case enrichment do
        {name, value} ->
          cond do
            [] == acc ->
              [enrichment]

            [head | tail] = acc ->
              cond do
                name == elem(head, 0) and is_list(value) and is_list(elem(head, 1)) ->
                  merged_value = [hd(value) | elem(head, 1)]
                  [{name, merged_value} | tail]

                true ->
                  [enrichment | acc]
              end
          end

        nil ->
          acc
      end
    end)
  end

  defp enrichments(%ResourceMapping{} = mapping, acc, {edge, dest_node})
       when is_list(acc) and is_map(edge) and is_map(dest_node) do
    dest_labels = Enum.into(dest_node.labels, [], &String.to_atom(&1))
    edge_label = String.to_atom(edge.type)
    edge_direction = edge_direction(edge, dest_node)

    dest_labels_filtered = List.delete(dest_labels, mapping.domain_label)

    relationship =
      Enum.find_value(dest_labels_filtered, fn dest_label ->
        case Enum.find(mapping.edges, fn ed ->
               ed.label == edge_label and ed.direction == edge_direction and
                 ed.destination_label == dest_label
             end) do
          nil -> nil
          ed -> Ash.Resource.Info.relationship(mapping.module, ed.relationship)
        end
      end)

    if relationship != nil do
      reverse_node_relationship = ResourceInfo.reverse_node_relationship(mapping.module, relationship.name)

      reverse_relationship =
        if reverse_node_relationship != nil do
          Ash.Resource.Info.relationship(relationship.destination, elem(reverse_node_relationship, 0))
        end

      cond do
        relationship.cardinality == :one && relationship.type == :belongs_to ->
          destination_property =
            ResourceInfo.convert_to_property_name(relationship.destination, relationship.destination_attribute)

          [
            {relationship.source_attribute, Map.get(dest_node.properties, destination_property)} | acc
          ]

        reverse_relationship != nil &&
            (reverse_relationship.cardinality == :one && reverse_relationship.type == :has_one) ->
          source_property =
            Keyword.get(mapping.properties, relationship.source_attribute, relationship.source_attribute)
            |> to_string()

          [
            {relationship.destination_attribute, Map.get(dest_node.properties, source_property)} | acc
          ]

        relationship.cardinality == :many && reverse_relationship != nil && reverse_relationship.cardinality == :many ->
          case convert_node_to_resource(relationship.destination, dest_node, []) do
            {:ok, dest_resource} ->
              [{relationship.name, [dest_resource]} | acc]

            {:error, reason} ->
              Logger.debug("AshNeo4j.DataLayer: unable to convert enrichment node: #{inspect(reason)}")
              acc
          end

        true ->
          acc
      end
    else
      acc
    end
  end

  defp edge_direction(edge, dest_node) when is_map(edge) and is_map(dest_node) do
    cond do
      dest_node.id == edge.start ->
        :incoming

      dest_node.id == edge.end ->
        :outgoing

      true ->
        nil
    end
  end

  defp convert_node_to_resource(subject, node, enrichments \\ [])

  defp convert_node_to_resource(%ResourceMapping{} = mapping, node, enrichments)
       when is_map(node) and is_list(enrichments) do
    convert_node_to_resource_impl(mapping.module, mapping.properties, node, enrichments)
  end

  defp convert_node_to_resource(resource, node, enrichments)
       when is_atom(resource) and is_map(node) and is_list(enrichments) do
    convert_node_to_resource_impl(resource, ResourceInfo.translations(resource), node, enrichments)
  end

  defp convert_node_to_resource_impl(resource, translations, node, enrichments)
       when is_atom(resource) and is_list(translations) and is_map(node) and is_list(enrichments) do
    enriched = Enum.into(enrichments, %{}, fn {field, value} -> {field, value} end)

    fields_result =
      Enum.reduce_while(translations, {:ok, enriched}, fn {resource_field, node_field}, {:ok, acc} ->
        property_value = read_attribute_property(resource, resource_field, node_field, node.properties)

        case cast_attribute(resource, resource_field, property_value) do
          {:ok, value} -> {:cont, {:ok, Map.put(acc, resource_field, value)}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case fields_result do
      {:error, reason} ->
        {:error, reason}

      {:ok, fields} ->
        belongs_to =
          Ash.Resource.Info.relationships(resource)
          |> Enum.filter(fn relationship ->
            relationship.type == :belongs_to and relationship.allow_nil?
          end)

        nilled_fields =
          Enum.reduce(belongs_to, fields, fn relationship, acc ->
            if Map.get(fields, relationship.source_attribute) == nil do
              acc |> Map.put(relationship.name, nil)
            else
              acc
            end
          end)

        {:ok,
         struct!(resource, nilled_fields)
         |> Ash.Resource.set_metadata(%{node_id: node.id, data_layer: __MODULE__, labels: node.labels})
         |> Ash.Resource.set_meta(struct(Ecto.Schema.Metadata, state: :loaded))}
    end
  end

  defp create_from_attributes(%ResourceMapping{} = mapping, attributes) when is_map(attributes) do
    properties = dump_properties(mapping, attributes)

    case create_node(mapping, properties) do
      {:ok, source_resource} ->
        relate_nodes(source_resource, mapping.module, attributes, mapping)

      {:error, error} ->
        {:error, error}
    end
  end

  defp relate_nodes(source_resource, resource, attributes, %ResourceMapping{} = mapping)
       when is_struct(source_resource) and is_atom(resource) and is_map(attributes) do
    relationship_attributes = mapping.relationship_attributes |> Keyword.delete(:id)
    relationship_source_attributes = Map.take(attributes, Keyword.keys(relationship_attributes))

    case Enum.count(relationship_source_attributes) do
      0 ->
        {:ok, source_resource}

      _ ->
        relationships =
          relationship_attributes
          |> Enum.reduce(
            [],
            fn {source_attribute, name}, acc ->
              relationship = Ash.Resource.Info.relationship(resource, name)
              dest_resource = relationship.destination

              case Enum.find(mapping.edges, &(&1.relationship == name)) do
                nil ->
                  acc

                %EdgeDescriptor{label: edge_label, direction: edge_direction, destination_label: destination_label} ->
                  dest_node_property_name =
                    Keyword.get(ResourceInfo.translations(dest_resource), relationship.destination_attribute)

                  dest_id_value = Map.get(relationship_source_attributes, source_attribute)

                  if dest_id_value == nil do
                    acc
                  else
                    dest_id = %{dest_node_property_name => dest_id_value}
                    exclusive = ResourceInfo.destination_exclusive?(resource, name)
                    [{destination_label, dest_id, edge_label, edge_direction, exclusive} | acc]
                  end
              end
            end
          )

        label = mapping.label_pair
        id_properties = id_properties(mapping, attributes)

        case Neo4jHelper.relate_nodes(label, id_properties, relationships) do
          :ok ->
            case Neo4jHelper.read_nodes_related(label, id_properties) do
              {:ok, %Bolty.Response{results: groups}} ->
                consolidated_groups = consolidate_groups(groups)

                cond do
                  length(consolidated_groups) == 1 ->
                    query = resource_to_query(resource, Ash.Resource.Info.domain(resource))
                    convert_to_resource(query, mapping, hd(consolidated_groups))

                  true ->
                    {:error, internal("expected enrichment groups to consolidate to a single resource")}
                end

              {:error, error} ->
                {:error, error}
            end

          {:error, error} ->
            {:error, error}
        end
    end
  end

  defp create_node(%ResourceMapping{} = mapping, properties) when is_map(properties) do
    case mapping.all_labels |> Neo4jHelper.create_node(properties) do
      {:ok, %Bolty.Response{results: [node_map | _]}} ->
        node = Map.get(node_map, "n")
        convert_node_to_resource(mapping.module, node)

      {:error, error} ->
        {:error, AshNeo4j.Error.Neo4j.from_bolt(error)}
    end
  end

  defp id_properties(%ResourceMapping{} = mapping, map) when is_map(map) do
    primary_keys = Ash.Resource.Info.primary_key(mapping.module)
    Enum.into(primary_keys, %{}, fn key -> {Keyword.get(mapping.properties, key, key), Map.get(map, key)} end)
  end

  defp relationship_properties(source_resource, dest_resource, source_map, dest_relationship_name)
       when is_atom(source_resource) and is_atom(dest_resource) and is_map(source_map) and
              is_atom(dest_relationship_name) do
    source_node_relationship = ResourceInfo.reverse_node_relationship(dest_resource, dest_relationship_name)

    if source_node_relationship != nil do
      source_relationship_name = elem(source_node_relationship, 0)
      source_relationship = Ash.Resource.Info.relationship(source_resource, source_relationship_name)
      value = Map.get(source_map, source_relationship.source_attribute)

      if value != nil do
        dest_property_name =
          ResourceInfo.convert_to_property_name(dest_resource, source_relationship.destination_attribute)
          |> String.to_atom()

        %{dest_property_name => value}
      else
        %{}
      end
    else
      %{}
    end
  end

  # Detects a many-to-many modelled as back-to-back `has_many` (#127): the source's
  # relationship is `has_many` AND the accessed resource declares a `has_many` back
  # to it, so one edge is described by two scalar FKs — which can't represent m2m.
  # (Their FKs aren't a clean inverse — which is *why* the resolution failed and we
  # land here — so this scans the relationships directly rather than relying on
  # `reverse_node_relationship`, which returns nil for exactly this shape.) Used to
  # turn the failure into an actionable error rather than a bare "couldn't relate
  # nodes". Joiner nodes are the supported shape; native many_to_many is #370.
  defp back_to_back_has_many?(resource, object_resource, object_relationship_name) do
    match?(%{type: :has_many}, Ash.Resource.Info.relationship(object_resource, object_relationship_name)) and
      Enum.any?(Ash.Resource.Info.relationships(resource), fn rel ->
        rel.destination == object_resource and rel.type == :has_many
      end)
  end

  # Property names to REMOVE on update: those the OLD value of each changed
  # attribute occupied that the NEW value no longer writes. Diffing the dumped
  # property KEYS of old vs new keeps removal exactly consistent with the write
  # path (dump_properties/2), and covers every companion-shape mismatch with one
  # mechanism:
  #
  #   * cleared to nil           — the new value writes nothing, so every old key
  #                                goes, including geo companions (#283)
  #   * geometry kind changed    — a Point's `<attr>.point` and an area's
  #                                `<attr>.bbSW`/`<attr>.bbNE` swap out (#287)
  #   * nested geo added/removed — dotted `<attr>.<path>.point|bbSW|bbNE`
  #                                companions the new value no longer promotes (#287)
  #
  # Only changed attributes are considered (unchanged ones keep their companions).
  # REMOVE of an absent property is a no-op; a key present in both old and new is
  # left in place for SET (`n += {…}`) to overwrite.
  defp stale_property_names(%ResourceMapping{} = mapping, new_properties, changeset)
       when is_map(new_properties) do
    old_properties =
      dump_properties(mapping, Map.take(changeset.data, Map.keys(changeset.attributes)))

    Map.keys(old_properties) -- Map.keys(new_properties)
  end

  def cast_attribute(_resource, _name, nil) do
    {:ok, nil}
  end

  def cast_attribute(resource, name, value) when is_atom(resource) and is_atom(name) do
    attribute = Ash.Resource.Info.attribute(resource, name)

    if attribute == nil do
      Logger.debug(
        "AshNeo4j.DataLayer: no attribute found for resource #{inspect(resource)} and name #{inspect(name)}, returning original value"
      )

      {:ok, value}
    else
      Cast.cast(attribute.type, value, attribute.constraints)
    end
  end

  # Rejects a write up front (#350) when an attribute carries a 3D areal/linear
  # geometry (PolygonZ, LineStringZ, …) — #270 supports 3D points only, and a 2D
  # bbox companion would silently drop the z. Walks top-level and nested geo via
  # `geo_walk`; returns `:ok` or `{:error, %Unsupported3DGeometry{}}`.
  defp validate_writable_geo(%ResourceMapping{} = mapping, attributes) when is_map(attributes) do
    Enum.find_value(mapping.properties, :ok, fn {key, translated_key} ->
      case Map.get(attributes, key) do
        nil ->
          nil

        value ->
          value
          |> geo_walk([translated_key])
          |> Enum.find_value(fn {_path, geo} -> unsupported_3d_geometry(geo) end)
      end
    end)
  end

  defp unsupported_3d_geometry(%struct{} = geo) do
    if struct != Geo.PointZ and geo_dim(geo) == 3 do
      {:error, AshNeo4j.Error.Unsupported3DGeometry.exception(geometry: struct)}
    end
  end

  defp dump_properties(%ResourceMapping{} = mapping, attributes) when is_map(attributes) do
    mapping.properties
    |> Enum.reduce(%{}, fn {key, translated_key}, acc ->
      value = Map.get(attributes, key)

      if value != nil do
        attribute = Ash.Resource.Info.attribute(mapping.module, key)

        attribute_type =
          Ash.Type.get_type!(attribute.type)

        dumped = Dump.dump(attribute_type, value, attribute.constraints)

        case TypeClassifier.classify(attribute_type) do
          {:ok, :geo, _} ->
            # Geo attribute: AshGeo's identity dump_to_native returned the
            # %Geo.*{} struct unchanged. Promote it into RFC 7946 JSON
            # canonical at <attr>.json + indexable companions (a native
            # Neo4j Point at <attr>.point for Geo.Point, or scalar
            # bbSW/bbNE for other geometries).
            promote_geo(acc, translated_key, dumped)

          {:ok, :tensor, tensor_type} ->
            # Tensor attribute: store just the bare flat value (Neo4j has no
            # nested-list property). Both type and shape are declared constraints
            # — schema, not stored — recovered on read, so no sidecar.
            store = attribute.constraints[:store] || :property
            Map.put(acc, translated_key, tensor_type.dump_storage(dumped, store))

          _ ->
            # Non-geo: dumped goes at the bare translated key.
            acc = Map.put(acc, translated_key, dumped)

            # Recursive geo-promotion: walk the *input* value (not the
            # dumped form, which may have been JSON-stringified) for any
            # nested %Geo.*{} structs and promote each one's indexable
            # companion to the node at its path. The canonical GeoJSON
            # for the nested geo lives inside the parent's JSON blob —
            # we only emit the indexable sidecar here. Path joining is
            # dotted (`<attr>.<field>...`) for namespace clarity.
            value
            |> geo_walk([translated_key])
            |> Enum.reduce(acc, fn {path, geo}, inner_acc ->
              promote_geo_indexable(inner_acc, Enum.join(path, "."), geo)
            end)
        end
      else
        acc
      end
    end)
  end

  # Promotes a %Geo.*{} struct into the **full** on-disk shape: RFC 7946
  # GeoJSON STRING canonical at <attr>.json + an indexable companion sized
  # to the geometry kind. Point gets a native Neo4j Point at <attr>.point
  # (preserves point.distance / point.withinBBox server-side pushdown);
  # any other geometry gets scalar bbSW/bbNE Points derived from the
  # bounding box (useful for bbox-prefilter pushdown).
  #
  # Used for top-level Geo attributes — the canonical lives at
  # <attr>.json because there's no enclosing JSON blob to nest inside.
  defp promote_geo(acc, translated_key, geo) do
    acc
    |> Map.put("#{translated_key}.json", AshNeo4j.GeoJson.encode!(geo))
    |> promote_geo_indexable(translated_key, geo)
  end

  # Promotes only the **indexable** companion for a %Geo.*{} — used when
  # a Geo struct is nested inside a non-Geo attribute (TypedStruct,
  # embedded resource, etc.). The canonical GeoJSON for the nested geo
  # lives inside the parent's JSON blob (via Util.to_json_safe's geo
  # handling), so we only need the indexable sidecar at the node level.
  defp promote_geo_indexable(acc, translated_key, %Geo.Point{coordinates: {x, y}}) do
    Map.put(acc, "#{translated_key}.point", Bolty.Types.Point.create(:wgs_84, x, y))
  end

  # WGS-84-3D point (#270) — native 3D Neo4j POINT (srid 4979) for `point.distance`
  # / `point.withinBBox` pushdown in 3D.
  defp promote_geo_indexable(acc, translated_key, %Geo.PointZ{coordinates: {x, y, z}}) do
    Map.put(acc, "#{translated_key}.point", Bolty.Types.Point.create(:wgs_84, x, y, z))
  end

  defp promote_geo_indexable(acc, translated_key, %_{} = geo) do
    cond do
      # 3D areal/linear geometries (PolygonZ, LineStringZ, …) are deferred to
      # #270 Phase 2 — silently storing 2D bbox companions would drop the z and
      # mislead spatial queries, so refuse explicitly rather than degrade.
      AshGeo.is_geo(geo.__struct__) and geo_dim(geo) == 3 ->
        # validate_writable_geo rejects these before write (#350), so this is
        # unreachable in practice — skip the (unrepresentable in 2D) indexable
        # sidecar rather than raise or drop the z via a bbox. The full geometry
        # is still preserved in the `.json` canonical written by promote_geo/3.
        acc

      AshGeo.is_geo(geo.__struct__) ->
        [west, south, east, north] = AshNeo4j.GeoJson.bbox(geo)

        acc
        |> Map.put("#{translated_key}.bbSW", Bolty.Types.Point.create(:wgs_84, west, south))
        |> Map.put("#{translated_key}.bbNE", Bolty.Types.Point.create(:wgs_84, east, north))

      true ->
        acc
    end
  end

  # Coordinate dimensionality of a %Geo.*{} struct (2 or 3), by inspecting the
  # first leaf coordinate tuple.
  defp geo_dim(%{coordinates: coords}), do: coord_dim(coords)
  defp coord_dim(t) when is_tuple(t), do: tuple_size(t)
  defp coord_dim([head | _]), do: coord_dim(head)
  defp coord_dim(_), do: 2

  # Recursively walks a value (typically the input form of a non-Geo
  # attribute — struct, map, etc.) looking for nested %Geo.*{} structs.
  # Returns a list of `{path :: [String.t()], geo :: %Geo.*{}}` pairs.
  # Path is the dotted hierarchy down to each Geo leaf, with the
  # outer-most attribute name supplied by the caller as the initial
  # path element.
  #
  # Arrays are skipped for now — union-bbox-over-array-elements is a
  # follow-up design question. The pattern extends cleanly when wanted.
  defp geo_walk(value, path)

  defp geo_walk(%struct{} = value, path) do
    if AshGeo.is_geo(struct) do
      [{path, value}]
    else
      value
      |> Map.from_struct()
      |> Enum.flat_map(fn {k, v} -> geo_walk(v, path ++ [to_string(k)]) end)
    end
  end

  defp geo_walk(map, path) when is_map(map) do
    Enum.flat_map(map, fn {k, v} -> geo_walk(v, path ++ [to_string(k)]) end)
  end

  defp geo_walk(_other, _path), do: []

  defp apply_aggregates_to_records(records, [], _resource), do: {:ok, records}

  defp apply_aggregates_to_records(records, aggregates, resource) do
    mapping = ResourceInfo.mapping(resource)
    pk_field = hd(Ash.Resource.Info.primary_key(resource))
    neo4j_pk = Keyword.get(mapping.properties, pk_field, pk_field)
    ids = Enum.map(records, &Map.get(&1, pk_field))

    Enum.reduce_while(aggregates, {:ok, records}, fn aggregate, {:ok, acc_records} ->
      case run_aggregate_for_ids(mapping, neo4j_pk, ids, aggregate, :per_record) do
        {:ok, agg_map} ->
          updated =
            Enum.map(acc_records, fn record ->
              id = Map.get(record, pk_field)
              value = Map.get(agg_map, id, aggregate.default_value)
              Map.put(record, aggregate.name, value)
            end)

          {:cont, {:ok, updated}}

        {:error, e} ->
          {:halt, {:error, e}}
      end
    end)
  end

  @doc """
  Read-time polymorphic projection (#329): for each source record, follows
  `chain` to the reached node(s) in one query (`related_nodes/4`) and projects
  each reached node to its concrete world via `AshNeo4j.worlds/1`.

  Returns `%{source_pk_value => projected}` where `projected` is the concrete
  record, an `AshNeo4j.Unknown` (a node was reached but its labels resolve to no
  loaded world), or `nil` (genuinely nothing reached). v1 is single-valued.
  """
  @spec project_traversal(module(), [Ash.Resource.record()], list()) :: %{optional(any()) => any()}
  def project_traversal(resource, records, chain) do
    mapping = ResourceInfo.mapping(resource)
    pk_field = hd(Ash.Resource.Info.primary_key(resource))
    neo4j_pk = Keyword.get(mapping.properties, pk_field, pk_field)
    ids = Enum.map(records, &Map.get(&1, pk_field))

    case AshNeo4j.QueryHelper.resolve_chain(resource, chain) do
      # A hop names no declared edge (#342) — can't project; surface Unknown.
      {:error, {:unresolved_hop, hop}} ->
        unknown = AshNeo4j.Unknown.new(resource, :unresolved_hop, %{hop: hop})
        Map.new(ids, &{&1, unknown})

      {:ok, {[], _reached}} ->
        Map.new(ids, &{&1, nil})

      {:ok, {segments, _reached}} ->
        query = CypherQuery.related_nodes(mapping.label_pair, neo4j_pk, ids, segments)

        case Cypher.run(query) do
          {:ok, %Bolty.Response{results: rows}} ->
            rows
            |> Enum.group_by(&Map.get(&1, "source_id"), &Map.get(&1, "dest_node"))
            |> Map.new(fn {source_id, dest_nodes} -> {source_id, project_reached(resource, dest_nodes)} end)

          {:error, reason} ->
            raise AshNeo4j.Error.Internal, detail: "traverse projection query failed: #{inspect(reason)}"
        end
    end
  end

  # v1 single-valued: the first reached node (or nil when none reached).
  defp project_reached(resource, dest_nodes) do
    case Enum.reject(dest_nodes, &is_nil/1) do
      [] -> nil
      [node | _] -> project_reached_node(resource, node)
    end
  end

  defp project_reached_node(resource, node) do
    case AshNeo4j.worlds(%{__metadata__: %{labels: node.labels}}) do
      [{_domain, concrete} | _] ->
        case convert_node_to_resource(concrete, node) do
          {:ok, record} -> record
          _ -> AshNeo4j.Unknown.new(resource, :projection_failed, %{labels: node.labels})
        end

      [] ->
        AshNeo4j.Unknown.new(resource, :no_concrete_world, %{labels: node.labels})
    end
  end

  defp apply_calculations_to_records(records, [], _resource), do: {:ok, records}

  defp apply_calculations_to_records(records, calculations, resource) do
    Enum.reduce_while(calculations, {:ok, records}, fn {calculation, expression}, {:ok, acc} ->
      case Ash.Filter.hydrate_refs(expression, %{resource: resource, public?: false, eval?: true}) do
        {:ok, hydrated} ->
          updated =
            Enum.map(acc, fn record ->
              case Ash.Expr.eval_hydrated(hydrated, record: record, resource: resource, unknown_on_unknown_refs?: true) do
                {:ok, value} -> Map.put(record, calculation.name, value)
                _ -> record
              end
            end)

          {:cont, {:ok, updated}}

        {:error, e} ->
          {:halt, {:error, e}}
      end
    end)
  end

  defp apply_calculation_sort(records, sort, _domain) when sort in [nil, []], do: records

  defp apply_calculation_sort(records, sort, domain) do
    if Enum.any?(sort, fn {term, _} -> is_struct(term, Ash.Query.Calculation) end) do
      Ash.Actions.Sort.runtime_sort(records, sort, domain: domain, rekey?: false)
    else
      records
    end
  end

  # No source nodes — return the empty value for the aggregate. `exists` over an
  # empty set is `false` (not the nil default Ash carries for it, #301); other
  # kinds use their declared default (`count` is 0).
  defp run_aggregate_for_ids(_mapping, _neo4j_pk, [], %{kind: :exists}, _mode) do
    {:ok, false}
  end

  defp run_aggregate_for_ids(_mapping, _neo4j_pk, [], aggregate, _mode) do
    {:ok, aggregate.default_value}
  end

  defp run_aggregate_for_ids(%ResourceMapping{} = mapping, neo4j_pk, ids, aggregate, mode) do
    case resolve_aggregate_path(mapping, aggregate.relationship_path) do
      {:ok, path_segments, dest_mapping} ->
        neo4j_field =
          if aggregate.field && is_atom(aggregate.field),
            do: Keyword.get(dest_mapping.properties, aggregate.field, aggregate.field),
            else: nil

        embedded = embedded_field_type(dest_mapping.module, aggregate.field)

        cond do
          # Expression-based aggregates always load full records in Elixir;
          # run_expr_agg handles aggregate.filter internally via apply_record_filter.
          is_struct(aggregate.field, Ash.Query.Calculation) ->
            run_expr_agg(mapping, neo4j_pk, ids, aggregate, mode, path_segments, dest_mapping)

          # When a filter is present, try to push scalar == conditions into Cypher.
          # Falls back to Elixir-side filtering for complex or embedded-field filters.
          aggregate_has_filter?(aggregate) ->
            case {simple_agg_filter(aggregate, dest_mapping), embedded} do
              {{:ok, dest_conditions}, nil} ->
                run_simple_filtered_aggregate(
                  mapping,
                  neo4j_pk,
                  ids,
                  aggregate,
                  mode,
                  path_segments,
                  neo4j_field,
                  dest_conditions
                )

              _ ->
                run_filtered_aggregate(mapping, neo4j_pk, ids, aggregate, mode, path_segments, dest_mapping)
            end

          embedded ->
            {field_type, field_constraints} = embedded

            run_embedded_agg(
              mapping,
              neo4j_pk,
              ids,
              aggregate,
              mode,
              path_segments,
              neo4j_field,
              field_type,
              field_constraints
            )

          true ->
            query =
              case mode do
                :per_record ->
                  CypherQuery.aggregate_per_record(
                    mapping.label_pair,
                    neo4j_pk,
                    ids,
                    path_segments,
                    aggregate.kind,
                    neo4j_field,
                    aggregate.name,
                    aggregate.uniq?
                  )

                :total ->
                  CypherQuery.aggregate_total(
                    mapping.label_pair,
                    neo4j_pk,
                    ids,
                    path_segments,
                    aggregate.kind,
                    neo4j_field,
                    aggregate.name,
                    aggregate.uniq?
                  )
              end

            case Cypher.run(query) do
              {:ok, %Bolty.Response{results: rows}} ->
                case mode do
                  :per_record ->
                    {:ok,
                     Map.new(rows, fn row ->
                       {Map.get(row, "source_id"), Map.get(row, to_string(aggregate.name))}
                     end)}

                  :total ->
                    value = rows |> List.first(%{}) |> Map.get(to_string(aggregate.name), aggregate.default_value)
                    {:ok, value}
                end

              {:error, e} ->
                {:error, e}
            end
        end

      {:error, e} ->
        {:error, e}
    end
  end

  # Handles any aggregate that carries a filter expression. Loads all destination
  # records for the given source IDs via Elixir, applies the Ash runtime filter,
  # then computes the aggregate in Elixir.
  #
  # This path is also used for expression-based aggregates (Ash.Query.Calculation
  # field) when a filter is present, because we already load full records there.
  defp run_filtered_aggregate(mapping, neo4j_pk, ids, aggregate, mode, path_segments, dest_mapping) do
    query = CypherQuery.related_nodes(mapping.label_pair, neo4j_pk, ids, path_segments)
    dest_resource = dest_mapping.module
    domain = Ash.Resource.Info.domain(dest_resource)

    with {:ok, %Bolty.Response{results: rows}} <- Cypher.run(query) do
      pairs =
        Enum.flat_map(rows, fn row ->
          source_id = Map.get(row, "source_id")
          dest_node = Map.get(row, "dest_node")

          if dest_node do
            case convert_node_to_resource(dest_resource, dest_node) do
              {:ok, record} -> [{source_id, record}]
              _ -> []
            end
          else
            []
          end
        end)

      case mode do
        :per_record ->
          grouped = Enum.group_by(pairs, &elem(&1, 0), &elem(&1, 1))

          result =
            Map.new(grouped, fn {source_id, records} ->
              {:ok, filtered} = Ash.Filter.Runtime.filter_matches(domain, records, aggregate.query.filter)
              values = extract_aggregate_field_values(filtered, aggregate)
              {source_id, apply_elixir_aggregate(aggregate.kind, values, aggregate.default_value)}
            end)

          {:ok, result}

        :total ->
          all_records = Enum.map(pairs, &elem(&1, 1))
          {:ok, filtered} = Ash.Filter.Runtime.filter_matches(domain, all_records, aggregate.query.filter)
          values = extract_aggregate_field_values(filtered, aggregate)
          {:ok, apply_elixir_aggregate(aggregate.kind, values, aggregate.default_value)}
      end
    end
  end

  # Handles aggregates whose filter is a set of simple scalar == conditions that can be
  # expressed as WHERE clauses in Cypher, avoiding full record loading in Elixir.
  defp run_simple_filtered_aggregate(mapping, neo4j_pk, ids, aggregate, mode, path_segments, neo4j_field, dest_conditions) do
    query =
      case mode do
        :per_record ->
          CypherQuery.aggregate_per_record(
            mapping.label_pair,
            neo4j_pk,
            ids,
            path_segments,
            aggregate.kind,
            neo4j_field,
            aggregate.name,
            aggregate.uniq?,
            dest_conditions
          )

        :total ->
          CypherQuery.aggregate_total(
            mapping.label_pair,
            neo4j_pk,
            ids,
            path_segments,
            aggregate.kind,
            neo4j_field,
            aggregate.name,
            aggregate.uniq?,
            dest_conditions
          )
      end

    case Cypher.run(query) do
      {:ok, %Bolty.Response{results: rows}} ->
        case mode do
          :per_record ->
            {:ok,
             Map.new(rows, fn row ->
               {Map.get(row, "source_id"), Map.get(row, to_string(aggregate.name))}
             end)}

          :total ->
            value = rows |> List.first(%{}) |> Map.get(to_string(aggregate.name), aggregate.default_value)
            {:ok, value}
        end

      {:error, e} ->
        {:error, e}
    end
  end

  # Returns {:ok, [{prop_string, value}]} when the aggregate filter consists entirely of
  # scalar == equality predicates on non-embedded destination attributes, enabling
  # WHERE pushdown into Cypher. Returns :complex otherwise and falls back to Elixir-side filtering.
  defp simple_agg_filter(aggregate, dest_mapping) do
    filter = aggregate_query_filter(aggregate)

    try do
      simple = Ash.Filter.to_simple_filter(filter, skip_invalid?: false)
      predicates = Map.get(simple, :predicates, [])

      if Enum.empty?(predicates) do
        :complex
      else
        Enum.reduce_while(predicates, {:ok, []}, fn predicate, {:ok, acc} ->
          cond do
            Map.get(predicate, :operator) != :== ->
              {:halt, :complex}

            not match?(%Ash.Query.Ref{}, Map.get(predicate, :left)) ->
              {:halt, :complex}

            match?(%Ash.Query.Calculation{}, Map.get(predicate.left, :attribute)) ->
              {:halt, :complex}

            true ->
              attr_name = Ash.Query.Ref.name(predicate.left)

              case embedded_field_type(dest_mapping.module, attr_name) do
                nil ->
                  prop = Keyword.get(dest_mapping.properties, attr_name, attr_name) |> to_string()
                  {:cont, {:ok, acc ++ [{prop, predicate.right}]}}

                _ ->
                  {:halt, :complex}
              end
          end
        end)
      end
    rescue
      _ -> :complex
    end
  end

  # Extracts the aggregate's target field value from each record, respecting uniq?.
  defp extract_aggregate_field_values(records, aggregate) do
    values =
      Enum.map(records, fn record ->
        case aggregate.field do
          nil -> record
          field when is_atom(field) -> Map.get(record, field)
          _ -> record
        end
      end)

    if aggregate.uniq?, do: Enum.uniq(values), else: values
  end

  defp embedded_field_type(resource_module, field_name) when is_atom(field_name) do
    case Ash.Resource.Info.attribute(resource_module, field_name) do
      nil ->
        nil

      attr ->
        type = Ash.Type.get_type(attr.type)

        case TypeClassifier.classify(type) do
          {:ok, :ash_json, _} -> {type, attr.constraints}
          _ -> nil
        end
    end
  end

  defp embedded_field_type(_, _), do: nil

  defp run_embedded_agg(
         mapping,
         neo4j_pk,
         ids,
         aggregate,
         mode,
         path_segments,
         neo4j_field,
         field_type,
         field_constraints
       ) do
    query =
      case mode do
        :per_record ->
          CypherQuery.aggregate_per_record(
            mapping.label_pair,
            neo4j_pk,
            ids,
            path_segments,
            :list,
            neo4j_field,
            aggregate.name,
            aggregate.uniq?
          )

        :total ->
          CypherQuery.aggregate_total(
            mapping.label_pair,
            neo4j_pk,
            ids,
            path_segments,
            :list,
            neo4j_field,
            aggregate.name,
            aggregate.uniq?
          )
      end

    case Cypher.run(query) do
      {:ok, %Bolty.Response{results: rows}} ->
        agg_key = to_string(aggregate.name)

        case mode do
          :per_record ->
            {:ok,
             Map.new(rows, fn row ->
               source_id = Map.get(row, "source_id")
               raw_list = Map.get(row, agg_key, [])
               cast_list = cast_raw_list(raw_list, field_type, field_constraints)
               {source_id, apply_elixir_aggregate(aggregate.kind, cast_list, aggregate.default_value)}
             end)}

          :total ->
            raw_list = rows |> List.first(%{}) |> Map.get(agg_key, [])
            cast_list = cast_raw_list(raw_list, field_type, field_constraints)
            {:ok, apply_elixir_aggregate(aggregate.kind, cast_list, aggregate.default_value)}
        end

      {:error, e} ->
        {:error, e}
    end
  end

  defp run_expr_agg(mapping, neo4j_pk, ids, aggregate, mode, path_segments, dest_mapping) do
    query = CypherQuery.related_nodes(mapping.label_pair, neo4j_pk, ids, path_segments)
    dest_resource = dest_mapping.module
    domain = Ash.Resource.Info.domain(dest_resource)
    calc = aggregate.field
    expr = calc.opts[:expr]

    case Ash.Filter.hydrate_refs(expr, %{resource: dest_resource, public?: false, eval?: true}) do
      {:ok, hydrated} ->
        case Cypher.run(query) do
          {:ok, %Bolty.Response{results: rows}} ->
            record_pairs =
              Enum.flat_map(rows, fn row ->
                source_id = Map.get(row, "source_id")
                dest_node = Map.get(row, "dest_node")

                if dest_node do
                  case convert_node_to_resource(dest_resource, dest_node) do
                    {:ok, record} -> [{source_id, record}]
                    _ -> []
                  end
                else
                  []
                end
              end)

            # Apply aggregate filter if present, then evaluate the expression.
            pairs =
              apply_record_filter(record_pairs, aggregate_query_filter(aggregate), domain)
              |> Enum.flat_map(fn {source_id, record} ->
                case Ash.Expr.eval_hydrated(hydrated,
                       record: record,
                       resource: dest_resource,
                       unknown_on_unknown_refs?: true
                     ) do
                  {:ok, value} when not is_nil(value) -> [{source_id, value}]
                  _ -> []
                end
              end)

            case mode do
              :per_record ->
                grouped = Enum.group_by(pairs, &elem(&1, 0), &elem(&1, 1))

                {:ok,
                 Map.new(grouped, fn {source_id, values} ->
                   {source_id, apply_elixir_aggregate(aggregate.kind, values, aggregate.default_value)}
                 end)}

              :total ->
                values = Enum.map(pairs, &elem(&1, 1))
                {:ok, apply_elixir_aggregate(aggregate.kind, values, aggregate.default_value)}
            end

          {:error, e} ->
            {:error, e}
        end

      {:error, e} ->
        {:error, e}
    end
  end

  # Returns true when the aggregate carries a real (non-trivial) filter in its
  # query. Ash always provides an Ash.Query on the aggregate; unfiltered aggregates
  # have %Ash.Filter{expression: true}. We only route through the Elixir-side
  # path when there is an actual user-defined filter to honour.
  defp aggregate_has_filter?(aggregate) do
    case aggregate_query_filter(aggregate) do
      %Ash.Filter{expression: true} -> false
      %Ash.Filter{} -> true
      _ -> false
    end
  end

  # Extracts the filter from aggregate.query, returning nil if absent.
  defp aggregate_query_filter(aggregate) do
    case Map.get(aggregate, :query) do
      %Ash.Query{filter: filter} -> filter
      _ -> nil
    end
  end

  # Applies an Ash filter (if any) to a list of {source_id, record} pairs,
  # keeping per-source grouping so filter predicates referencing destination
  # attributes are evaluated correctly.
  defp apply_record_filter(pairs, nil, _domain), do: pairs

  defp apply_record_filter(pairs, filter, domain) do
    grouped = Enum.group_by(pairs, &elem(&1, 0), &elem(&1, 1))

    Enum.flat_map(grouped, fn {source_id, records} ->
      {:ok, filtered} = Ash.Filter.Runtime.filter_matches(domain, records, filter)
      Enum.map(filtered, &{source_id, &1})
    end)
  end

  defp cast_raw_list(raw_list, field_type, field_constraints) when is_list(raw_list) do
    case Cast.cast({:array, field_type}, raw_list, field_constraints) do
      {:ok, values} -> values
      {:error, _} -> []
    end
  end

  defp cast_raw_list(_, _, _), do: []

  defp apply_elixir_aggregate(:list, values, _default), do: values
  defp apply_elixir_aggregate(:first, values, default), do: List.first(values, default)
  defp apply_elixir_aggregate(:count, values, _default), do: length(values)
  defp apply_elixir_aggregate(:exists, values, _default), do: values != []
  defp apply_elixir_aggregate(:sum, [], default), do: default
  defp apply_elixir_aggregate(:sum, values, _default), do: Enum.sum(values)
  defp apply_elixir_aggregate(:avg, [], default), do: default
  defp apply_elixir_aggregate(:avg, values, _default), do: Enum.sum(values) / length(values)
  defp apply_elixir_aggregate(:min, [], default), do: default
  defp apply_elixir_aggregate(:min, values, _default), do: Enum.min(values)
  defp apply_elixir_aggregate(:max, [], default), do: default
  defp apply_elixir_aggregate(:max, values, _default), do: Enum.max(values)

  defp resolve_aggregate_path(%ResourceMapping{} = mapping, relationship_path) do
    Enum.reduce_while(relationship_path, {mapping, []}, fn name, {current_mapping, segments} ->
      case Enum.find(current_mapping.edges, &(&1.relationship == name)) do
        nil ->
          {:halt, {:error, internal("relationship #{name} not found on #{inspect(current_mapping.module)}")}}

        %EdgeDescriptor{label: edge_label, direction: direction, destination_label: dest_label} ->
          relationship = Ash.Resource.Info.relationship(current_mapping.module, name)
          next_mapping = ResourceInfo.mapping(relationship.destination)
          {:cont, {next_mapping, [{edge_label, direction, dest_label} | segments]}}
      end
    end)
    |> case do
      {:error, _} = error -> error
      {dest_mapping, segments} -> {:ok, Enum.reverse(segments), dest_mapping}
    end
  end
end
