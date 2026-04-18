# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Util do
  @moduledoc """
  AshNeo4j Util
  """

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

  defp to_json_safe(struct) when is_struct(struct) do
    struct
    |> Map.from_struct()
    |> to_json_safe()
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
end
