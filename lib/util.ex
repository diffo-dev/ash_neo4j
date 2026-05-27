# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Util do
  @moduledoc """
  AshNeo4j Util
  """
  require AshGeo

  # RFC 7946 §3.1 geometry types — fast-path check before invoking
  # Geo.JSON.decode on a map. Keeps the restore_geo walker cheap on
  # non-geo data.
  @geojson_geometry_types ~w[
    Point
    LineString
    Polygon
    MultiPoint
    MultiLineString
    MultiPolygon
    GeometryCollection
  ]

  @doc """
  Converts an Elixir snake_case atom to Neo4j camelCase atom, used for node properties

  ## Examples
  ```
  iex> AshNeo4j.Util.to_camel_case(:snake_case)
  :snakeCase
  iex> AshNeo4j.Util.to_camel_case(:UUID)
  :uuid
  ```
  """
  def to_camel_case(atom) when is_atom(atom) do
    splits = String.split(Atom.to_string(atom), "_")
    (String.downcase(hd(splits)) <> Enum.map_join(tl(splits), "", fn s -> String.capitalize(s) end)) |> String.to_atom()
  end

  @doc """
  Converts an Elixir snake_case atom to Neo4j PascalCase atom, used for node labels

  ## Examples
  ```
  iex> AshNeo4j.Util.to_pascal_case(:snake_case)
  :SnakeCase
  iex> AshNeo4j.Util.to_pascal_case(:domain)
  :Domain
  ```
  """
  def to_pascal_case(atom) when is_atom(atom) do
    splits = String.split(Atom.to_string(atom), "_")

    (String.capitalize(hd(splits)) <> Enum.map_join(tl(splits), "", fn s -> String.capitalize(s) end))
    |> String.to_atom()
  end

  @doc """
  Converts an Elixir snake_case atom to Neo4j MACRO_CASE atom, used for edge labels

  ## Examples
  ```
  iex> AshNeo4j.Util.to_macro_case(:snake_case)
  :SNAKE_CASE
  iex> AshNeo4j.Util.to_macro_case(:belongs_to)
  :BELONGS_TO
  ```
  """
  def to_macro_case(atom) when is_atom(atom) do
    String.upcase(Atom.to_string(atom)) |> String.to_atom()
  end

  @doc """
  Returns the short name for an Elixir Module

  ## Examples
  ```
  iex> AshNeo4j.Util.short_name(MyApp.Domain.User)
  :User
  ```
  """
  def short_name(module) when is_atom(module) do
    module |> Atom.to_string() |> String.split(".") |> List.last() |> String.to_atom()
  end

  @doc """
  Validates that an atom is a valid Neo4j property name (i.e. does not start with a number and does not contain spaces or special characters)

  ## Examples
  ```
  iex> AshNeo4j.Util.is_valid_property_name?(:validName)
  true
  iex> AshNeo4j.Util.is_valid_property_name?(:invalid_name)
  false
  ```
  """
  def is_valid_property_name?(atom) when is_atom(atom) do
    name = Atom.to_string(atom)
    Regex.match?(~r/^[a-z][a-zA-Z0-9]*$/, name)
  end

  @doc """
  Validates that an atom is a valid Neo4j node label (i.e. starts with an uppercase letter and contains only letters and numbers)

  ## Examples
  ```
  iex> AshNeo4j.Util.is_valid_node_label?(:ValidLabel)
  true
  iex> AshNeo4j.Util.is_valid_node_label?(:invalid_label)
  false
  ```
  """
  def is_valid_node_label?(atom) when is_atom(atom) do
    name = Atom.to_string(atom)
    Regex.match?(~r/^[A-Z][a-zA-Z0-9]*$/, name)
  end

  @doc """
  Validates that an atom is a valid Neo4j edge label (i.e. contains only uppercase letters and underscores)

  ## Examples
  ```
  iex> AshNeo4j.Util.is_valid_edge_label?(:VALID_LABEL)
  true
  iex> AshNeo4j.Util.is_valid_edge_label?(:invalid_label)
  false
  ```
  """
  def is_valid_edge_label?(atom) when is_atom(atom) do
    name = Atom.to_string(atom)
    Regex.match?(~r/^[A-Z]+(_[A-Z]+)*$/, name)
  end

  @doc """
  Returns the reverse direction
  """
  def reverse(direction) when is_atom(direction) do
    case direction do
      :incoming -> :outgoing
      :outgoing -> :incoming
      _ -> nil
    end
  end

  @doc """
  Whether the given module uses Ash.TypedStruct

  ## Examples
  ```
  iex> AshNeo4j.Util.typed_struct?(AshNeo4j.Test.Type.DogTypedStruct)
  true
  iex> AshNeo4j.Util.typed_struct?(List)
  false
  ```
  """
  def typed_struct?(module) do
    Spark.Dsl.is?(module, Ash.TypedStruct)
  rescue
    _ -> false
  end

  @doc """
  Encodes json, converting structs and maps to ordered objects sorted by key, even when in lists/nested
  Deliberately does not call Jason.Encoder on structs, since Protocol may not be implemented for persistence/at all

  ## Examples
  ```
  iex> AshNeo4j.Util.json_encode(%{name: "Henry", age: 8, breed: :groodle})
  {:ok, ~s({"age":8,"breed":"groodle","name":"Henry"})}
  iex> AshNeo4j.Util.json_encode([%{currency: :aud, amount: 100}, %{currency: :sek, amount: 650}])
  {:ok, ~s([{"amount":100,"currency":"aud"},{"amount":650,"currency":"sek"}])}
  iex> AshNeo4j.Util.json_encode(%Ash.Union{type: :typed_struct, value: %AshNeo4j.Test.Type.DogTypedStruct{name: "Henry", age: 8, breed: "groodle"}})
  {:ok, ~s({"type":"typed_struct","value":{"age":8,"breed":"groodle","name":"Henry"}})}
  ```
  """
  def json_encode(value) do
    value
    |> to_json_safe()
    |> Jason.encode()
  end

  # Geo structs (Geo.Point, Geo.LineString, Geo.Polygon, Geo.MultiPoint,
  # etc.) carry tuple-shaped coordinates that Jason can't encode directly.
  # Route them through AshNeo4j.GeoJson.encode_map/1 to get an RFC 7946
  # GeoJSON map (with bbox member), then recurse — keeps the inner
  # GeoJSON nested inside whatever parent struct is being encoded.
  defp to_json_safe(%struct{} = geo) do
    if AshGeo.is_geo(struct) do
      geo |> AshNeo4j.GeoJson.encode_map() |> to_json_safe()
    else
      geo |> Map.from_struct() |> to_json_safe()
    end
  end

  defp to_json_safe(map) when is_map(map) and not is_struct(map) do
    map
    |> Enum.reduce([], fn {k, v}, acc ->
      if is_nil(v), do: acc, else: [{to_string(k), to_json_safe(v)} | acc]
    end)
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Jason.OrderedObject.new()
  end

  defp to_json_safe(list) when is_list(list) do
    Enum.map(list, &to_json_safe/1)
  end

  defp to_json_safe(atom) when is_atom(atom) and not is_nil(atom) and not is_boolean(atom) do
    to_string(atom)
  end

  defp to_json_safe(value), do: value

  def base64_decode(value) do
    case Base.decode64(value) do
      {:ok, decoded} -> {:ok, decoded}
      _ -> {:error, "AshNeo4j.DataLayer: cannot decode Base64 value #{inspect(value)}"}
    end
  end

  def json_decode(value) do
    case Jason.decode(value) do
      {:ok, decoded} -> {:ok, restore_geo(decoded)}
      {:error, reason} -> {:error, "AshNeo4j.DataLayer: cannot decode JSON value #{inspect(value)}: #{inspect(reason)}"}
    end
  end

  # Walks a decoded JSON structure looking for GeoJSON-shaped sub-maps
  # (which `to_json_safe` produces when it encounters a `%Geo.*{}` struct
  # nested inside another value) and converts each back to a `%Geo.*{}`
  # via `Geo.JSON.decode/1`. Round-trip symmetric with the write-side
  # transformation in `to_json_safe`.
  #
  # This is a local workaround for `AshGeo.GeoJson.cast_stored/2` being
  # strict — it accepts `%Geo.*{}` structs only, not maps, even though
  # `cast_input/2` is map-permissive. When TypedStruct (or any
  # JSON-stored type containing an AshGeo field) walks its fields on
  # cast_stored, each AshGeo field would otherwise see a GeoJSON map
  # and fail. This restores Geo structs before the type sees them.
  #
  # Upstream issue/PR to be filed against bcksl/ash_geo (cc Zach as the
  # other AshGeo contributor) — once `cast_stored` handles maps natively,
  # this can be removed.
  defp restore_geo(%{"type" => type} = map) when type in @geojson_geometry_types do
    case Geo.JSON.decode(map) do
      # AshNeo4j is WGS-84 2D throughout; Geo.JSON.decode produces structs
      # with srid: nil (the on-disk RFC 7946 JSON omits the crs member per
      # the spec — that's what we want on disk but it loses the srid on
      # read). Set srid: 4326 here so the round-trip restores faithfully.
      {:ok, geo} -> %{geo | srid: 4326}
      _ -> recurse_geo(map)
    end
  end

  defp restore_geo(map) when is_map(map), do: recurse_geo(map)
  defp restore_geo(list) when is_list(list), do: Enum.map(list, &restore_geo/1)
  defp restore_geo(value), do: value

  defp recurse_geo(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {k, restore_geo(v)} end)
  end
end
