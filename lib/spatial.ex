# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Spatial do
  @moduledoc """
  Convenience helpers for creating the Neo4j POINT indexes that back
  AshNeo4j's spatial pushdown (#275).

  After #274, the indexable form of a geometry is a scalar Neo4j POINT
  companion that the data layer writes automatically alongside the
  canonical RFC 7946 GeoJSON:

    * a `%Geo.Point{}` gets one companion at `<property>.point`;
    * any other geometry gets two, `<property>.bbSW` / `<property>.bbNE`
      (the bounding-box corners `point.withinBBox` reads).

  Hand-writing the index Cypher means knowing the resource's Neo4j
  **label**, the attribute → **property** translation, the **companion
  suffix** convention, and — for bbox geometries — that there are *two*
  companions. This module applies that internal knowledge for you,
  resolving everything from the resource module and attribute name.

      # top-level Point attribute → one `.point` index
      AshNeo4j.Spatial.create_index(Place, :location)

      # non-Point geometry → both bbSW and bbNE indexes
      AshNeo4j.Spatial.create_index(Place, :bounds)

      # nested geometry — [attribute, field...] path into a TypedStruct
      AshNeo4j.Spatial.create_index(Place, [:pet, :home])

      # rebuild (DROP IF EXISTS + CREATE) after a storage-shape change
      AshNeo4j.Spatial.create_index(Place, :location, recreate: true)

  Consistent with AshNeo4j's "no migrations, index lifecycle is the
  operator's concern" stance (#45) — this is an ergonomic tool you
  *choose* to call (e.g. from a start-up task), not automatic
  behaviour. `create_index/3` uses `IF NOT EXISTS`, so it's safe to run
  repeatedly. Indexes are schema objects independent of data: clearing
  nodes does not drop them, and they re-populate as nodes are written.

  ## Naming

  Each companion gets its own index named `<base>_<suffix>`, where
  `suffix` is `point` / `bbSW` / `bbNE` and `base` defaults to
  `<label>_<dotted_property>` (label lower-cased, dots as underscores) —
  e.g. `place_location_point`, `place_bounds_bbSW`. Pass `name:` to
  override the base.

  ## Dry run

  `index_statements/3` returns the exact `CREATE` Cypher without
  touching the database — useful for review, a migration file, or
  testing.
  """

  alias AshNeo4j.Cypher
  alias AshNeo4j.DataLayer.TypeClassifier
  alias AshNeo4j.Resource.Info, as: ResourceInfo

  @typedoc "An attribute name, or a `[attribute, field, ...]` path into a nested geometry."
  @type attr_or_path :: atom() | [atom()]

  @doc """
  Creates the POINT index(es) backing spatial pushdown for `attr_or_path`.

  Returns `{:ok, responses}` — a list with one `%Bolty.Response{}` per
  index created (one for a Point, two for a bbox geometry) — or
  `{:error, reason}` on the first failure or if the attribute can't be
  resolved to a geometry.

  ## Options

    * `:recreate` — when `true`, `DROP INDEX ... IF EXISTS` precedes each
      `CREATE`. Needed only when the index *definition* changes; data
      churn never requires it. Defaults to `false`.
    * `:name` — override the auto-derived base index name. The companion
      suffix (`_point` / `_bbSW` / `_bbNE`) is still appended.
  """
  @spec create_index(Ash.Resource.t(), attr_or_path(), keyword()) ::
          {:ok, [Bolty.Response.t()]} | {:error, term()}
  def create_index(resource, attr_or_path, opts \\ []) do
    recreate? = Keyword.get(opts, :recreate, false)

    with {:ok, specs} <- resolve_specs(resource, attr_or_path, Keyword.get(opts, :name)) do
      run_each(specs, fn spec ->
        if recreate? do
          run_all([drop_cypher(spec), create_cypher(spec)])
        else
          Cypher.run(create_cypher(spec))
        end
      end)
    end
  end

  @doc """
  Drops the POINT index(es) for `attr_or_path` (both corners for a bbox
  geometry). Uses `IF EXISTS`, so it's a no-op when absent.

  Returns `{:ok, responses}` or `{:error, reason}`. Pass `:name` to match
  a base name overridden at create time.
  """
  @spec drop_index(Ash.Resource.t(), attr_or_path(), keyword()) ::
          {:ok, [Bolty.Response.t()]} | {:error, term()}
  def drop_index(resource, attr_or_path, opts \\ []) do
    with {:ok, specs} <- resolve_specs(resource, attr_or_path, Keyword.get(opts, :name)) do
      run_each(specs, fn spec -> Cypher.run(drop_cypher(spec)) end)
    end
  end

  @doc """
  Returns `{:ok, statements}` — the `CREATE POINT INDEX` Cypher that
  `create_index/3` would run — without touching the database, or
  `{:error, reason}`. Honours `:name`; ignores `:recreate`.

      AshNeo4j.Spatial.index_statements(Place, :location)
      #=> {:ok, ["CREATE POINT INDEX place_location_point IF NOT EXISTS FOR (n:Place) ON (n.`location.point`)"]}
  """
  @spec index_statements(Ash.Resource.t(), attr_or_path(), keyword()) ::
          {:ok, [String.t()]} | {:error, term()}
  def index_statements(resource, attr_or_path, opts \\ []) do
    with {:ok, specs} <- resolve_specs(resource, attr_or_path, Keyword.get(opts, :name)) do
      {:ok, Enum.map(specs, &create_cypher/1)}
    end
  end

  # --- resolution ------------------------------------------------------

  # A spec is one index to create/drop: %{name, label, property}.
  defp resolve_specs(resource, attr_or_path, name_override) do
    with {:ok, label} <- resolve_label(resource),
         [attr | segments] when is_atom(attr) <- List.wrap(attr_or_path),
         {:ok, attribute} <- resolve_attribute(resource, attr),
         {:ok, geo_types} <- walk_to_geo(attribute.type, attribute.constraints, segments, [attr]) do
      translated = ResourceInfo.translations(resource) |> Keyword.get(attr, attr)
      base_path = Enum.map_join([translated | segments], ".", &to_string/1)
      base_name = name_override || default_base_name(label, base_path)

      specs =
        for suffix <- companion_suffixes(geo_types) do
          %{name: "#{base_name}_#{suffix}", label: label, property: "#{base_path}.#{suffix}"}
        end

      {:ok, specs}
    else
      [] -> {:error, "AshNeo4j.Spatial: attribute path is empty"}
      [other | _] -> {:error, "AshNeo4j.Spatial: path elements must be atoms, got #{inspect(other)}"}
      {:error, _} = error -> error
    end
  end

  defp resolve_label(resource) do
    case ResourceInfo.module_label(resource) do
      nil ->
        {:error, "AshNeo4j.Spatial: #{inspect(resource)} has no Neo4j module label — is it an AshNeo4j resource?"}

      label ->
        {:ok, label}
    end
  end

  defp resolve_attribute(resource, attr) do
    case Ash.Resource.Info.attribute(resource, attr) do
      nil -> {:error, "AshNeo4j.Spatial: #{inspect(resource)} has no attribute #{inspect(attr)}"}
      attribute -> {:ok, attribute}
    end
  end

  # Leaf: the type here must be an ash_geo geometry carrying a
  # :geo_types constraint (that's what tells us point vs bbox shape).
  defp walk_to_geo(type, constraints, [], path) do
    cond do
      not TypeClassifier.ash_geo_type?(type) ->
        {:error,
         "AshNeo4j.Spatial: #{dotted(path)} is #{inspect(type)}, not an ash_geo geometry " <>
           "(AshGeo.GeoJson / GeoAny / ...). Only geometry attributes carry indexable companions."}

      true ->
        case List.wrap(Keyword.get(constraints || [], :geo_types)) do
          [] ->
            {:error,
             "AshNeo4j.Spatial: #{dotted(path)} has no :geo_types constraint, so the companion " <>
               "shape (point vs bbox) can't be inferred — add e.g. constraints: [geo_types: [:point]]."}

          geo_types ->
            {:ok, geo_types}
        end
    end
  end

  # Descend one nested field segment (Ash.TypedStruct field) and recurse.
  defp walk_to_geo(type, _constraints, [segment | rest], path) do
    case typed_struct_field(type, segment) do
      {:ok, field_type, field_constraints} ->
        walk_to_geo(field_type, field_constraints, rest, path ++ [segment])

      :error ->
        {:error,
         "AshNeo4j.Spatial: can't descend into #{dotted(path)} (#{inspect(type)}) to reach " <>
           "#{inspect(segment)} — nested indexing supports Ash.TypedStruct fields."}
    end
  end

  defp typed_struct_field(type, segment) do
    case Enum.find(typed_struct_fields(type), &(&1.name == segment)) do
      %{type: field_type, constraints: field_constraints} -> {:ok, field_type, field_constraints}
      nil -> :error
    end
  end

  defp typed_struct_fields(module) do
    if is_atom(module) and Code.ensure_loaded?(module) do
      try do
        Ash.TypedStruct.Info.fields(module)
      rescue
        _ -> []
      end
    else
      []
    end
  end

  # --- companion shape -------------------------------------------------

  # Point-shaped geometries (2D `%Geo.Point{}` and 3D `%Geo.PointZ{}`, #270)
  # promote to a single `.point` companion (a native Neo4j POINT); every other
  # geometry promotes to `.bbSW` / `.bbNE`. A mixed-type attribute
  # (e.g. geo_types: [:point, :polygon]) can store either shape, so we
  # index all companions it could ever produce.
  @point_geo_types [:point, :point_z, :point_zm]

  defp companion_suffixes(geo_types) do
    types = List.wrap(geo_types)
    point = if Enum.any?(types, &(&1 in @point_geo_types)), do: ["point"], else: []
    bbox = if Enum.any?(types, &(&1 not in @point_geo_types)), do: ["bbSW", "bbNE"], else: []
    point ++ bbox
  end

  defp default_base_name(label, base_path) do
    "#{label |> to_string() |> String.downcase()}_#{String.replace(base_path, ".", "_")}"
  end

  # --- cypher ----------------------------------------------------------

  defp create_cypher(%{name: name, label: label, property: property}) do
    "CREATE POINT INDEX #{name} IF NOT EXISTS FOR (n:#{label}) ON (n.`#{property}`)"
  end

  defp drop_cypher(%{name: name}), do: "DROP INDEX #{name} IF EXISTS"

  defp dotted(path), do: Enum.map_join(path, ".", &to_string/1)

  # --- execution -------------------------------------------------------

  defp run_each(specs, fun) do
    specs
    |> Enum.reduce_while({:ok, []}, fn spec, {:ok, acc} ->
      case fun.(spec) do
        {:ok, response} -> {:cont, {:ok, [response | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      {:error, _} = error -> error
    end
  end

  defp run_all(statements) do
    statements
    |> Enum.reduce_while({:ok, nil}, fn cypher, _acc ->
      case Cypher.run(cypher) do
        {:ok, response} -> {:cont, {:ok, response}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end
end
