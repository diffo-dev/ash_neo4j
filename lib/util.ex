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
  Whether the given module uses Ash.TypedStruct

  ## Examples
  ```
  iex> AshNeo4j.Util.typed_struct?(Ash.TypedStruct)
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
  Encodes json, encoding maps which aren't structs with keys in sorted order, even in lists
  ## Examples
  ```
  iex> AshNeo4j.Util.json_encode(%{name: "Henry", age: 8, breed: :groodle})
  "{:ok, {\"age\":8,\"breed\":\"groodle\",\"name\":\"Henry\"}}"
  iex> AshNeo4j.Util.json_encode([%{currency: :aud, amount: 100}, %{currency: :sek, amount: 650}])
  "{:ok, [{\"amount\":100,\"currency\":\"aud\"},{\"amount\":650,\"currency\":\"sek\"}]}"

  """

  def json_encode(struct) when is_struct(struct), do: Jason.encode(struct)

  def json_encode(map) when is_map(map) do
    map
    |> Enum.sort_by(&elem(&1, 0))
    |> Jason.OrderedObject.new()
    |> json_encode()
  end

  def json_encode(list) when is_list(list) do
    list
    |> Enum.reduce_while(
      "",
      fn item, acc ->
        case json_encode(item) do
          {:ok, encoded} ->
            if acc == "" do
              {:cont, "[" <> encoded}
            else
              {:cont, acc <> "," <> encoded}
            end

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end
    )
    |> case do
      {:error, reason} -> {:error, reason}
      encoded -> {:ok, encoded <> "]"}
    end
  end

  def json_encode(value), do: Jason.encode(value)
end
