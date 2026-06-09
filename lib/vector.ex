# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Vector do
  @moduledoc """
  Convenience helpers for creating the Neo4j VECTOR indexes that back
  `AshNeo4j.Type.Vector` attributes.

  Requires Cypher 25 (Neo4j ≥ 2025.06). Operations against an older server
  raise `AshNeo4j.Error.RequiresCypher25`.

      # Create the index for a vector attribute
      AshNeo4j.Vector.create_index(Item, :embedding)

      # Rebuild after a dimension or similarity-function change
      AshNeo4j.Vector.create_index(Item, :embedding, recreate: true)

      # Euclidean distance instead of the default cosine
      AshNeo4j.Vector.create_index(Item, :embedding, similarity_function: :euclidean)

  Consistent with AshNeo4j's "no automatic migrations" stance — this is an
  ergonomic tool you call (e.g. from a start-up task). `create_index/3` uses
  `IF NOT EXISTS`, so it is safe to run repeatedly.

  ## Naming

  The index is named `<base>_vector` where `base` defaults to
  `<label_lower>_<property>` — e.g. `item_embedding_vector`. Pass `:name` to
  override the base.

  ## Dry run

  `index_statements/3` returns the `CREATE` Cypher without touching the
  database — useful for review or testing.
  """

  alias AshNeo4j.Cypher
  alias AshNeo4j.Resource.Info, as: ResourceInfo

  @doc """
  Creates the VECTOR index for `attr` on `resource`.

  Returns `{:ok, %Bolty.Response{}}` or `{:error, reason}`.

  ## Options

    * `:recreate` — `DROP INDEX ... IF EXISTS` before `CREATE`. Use after changing
      `:dimensions` or `:similarity_function`. Defaults to `false`.
    * `:name` — override the auto-derived base name. `_vector` is still appended.
    * `:similarity_function` — `:cosine` (default) or `:euclidean`.
  """
  @spec create_index(Ash.Resource.t(), atom(), keyword()) ::
          {:ok, Bolty.Response.t()} | {:error, term()}
  def create_index(resource, attr, opts \\ []) do
    Cypher.require_cypher25!()

    with {:ok, spec} <- resolve_spec(resource, attr, opts) do
      if Keyword.get(opts, :recreate, false) do
        with {:ok, _} <- Cypher.run(drop_cypher(spec)), do: Cypher.run(create_cypher(spec))
      else
        Cypher.run(create_cypher(spec))
      end
    end
  end

  @doc """
  Drops the VECTOR index for `attr`. Uses `IF EXISTS`, so it is a no-op when absent.
  """
  @spec drop_index(Ash.Resource.t(), atom(), keyword()) ::
          {:ok, Bolty.Response.t()} | {:error, term()}
  def drop_index(resource, attr, opts \\ []) do
    Cypher.require_cypher25!()

    with {:ok, spec} <- resolve_spec(resource, attr, opts) do
      Cypher.run(drop_cypher(spec))
    end
  end

  @doc """
  Returns `{:ok, statement}` — the `CREATE VECTOR INDEX` Cypher that
  `create_index/3` would run — without touching the database.

      AshNeo4j.Vector.index_statements(Item, :embedding)
      #=> {:ok, "CREATE VECTOR INDEX item_embedding_vector IF NOT EXISTS FOR (n:Item) ON (n.embedding) OPTIONS {indexConfig: {`vector.dimensions`: 1536, `vector.similarity_function`: 'cosine'}}"}
  """
  @spec index_statements(Ash.Resource.t(), atom(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def index_statements(resource, attr, opts \\ []) do
    with {:ok, spec} <- resolve_spec(resource, attr, opts) do
      {:ok, create_cypher(spec)}
    end
  end

  # --- guards ------------------------------------------------------------


  # --- resolution --------------------------------------------------------

  defp resolve_spec(resource, attr, opts) do
    with {:ok, label} <- resolve_label(resource),
         {:ok, attribute} <- resolve_attribute(resource, attr),
         {:ok, dimensions} <- resolve_dimensions(attribute, attr) do
      translated = ResourceInfo.translations(resource) |> Keyword.get(attr, attr)
      property = to_string(translated)
      base = opts[:name] || default_base_name(label, property)
      similarity = opts[:similarity_function] || :cosine

      {:ok,
       %{
         name: "#{base}_vector",
         label: label,
         property: property,
         dimensions: dimensions,
         similarity: similarity
       }}
    end
  end

  defp resolve_label(resource) do
    case ResourceInfo.module_label(resource) do
      nil ->
        {:error,
         "AshNeo4j.Vector: #{inspect(resource)} has no Neo4j module label — is it an AshNeo4j resource?"}

      label ->
        {:ok, label}
    end
  end

  defp resolve_attribute(resource, attr) do
    case Ash.Resource.Info.attribute(resource, attr) do
      nil -> {:error, "AshNeo4j.Vector: #{inspect(resource)} has no attribute #{inspect(attr)}"}
      attribute -> {:ok, attribute}
    end
  end

  defp resolve_dimensions(attribute, attr) do
    case attribute.type do
      AshNeo4j.Type.Vector ->
        case Keyword.get(attribute.constraints || [], :dimensions) do
          nil ->
            {:error,
             "AshNeo4j.Vector: attribute #{inspect(attr)} has no :dimensions constraint — " <>
               "add `constraints: [dimensions: N]` to set the vector size"}

          dims ->
            {:ok, dims}
        end

      other ->
        {:error,
         "AshNeo4j.Vector: attribute #{inspect(attr)} is #{inspect(other)}, not AshNeo4j.Type.Vector"}
    end
  end

  defp default_base_name(label, property) do
    "#{label |> to_string() |> String.downcase()}_#{String.replace(property, ".", "_")}"
  end

  # --- cypher ------------------------------------------------------------

  defp create_cypher(%{name: name, label: label, property: property, dimensions: dims, similarity: similarity}) do
    "CREATE VECTOR INDEX #{name} IF NOT EXISTS " <>
      "FOR (n:#{label}) ON (n.#{property}) " <>
      "OPTIONS {indexConfig: {`vector.dimensions`: #{dims}, `vector.similarity_function`: '#{similarity}'}}"
  end

  defp drop_cypher(%{name: name}), do: "DROP INDEX #{name} IF EXISTS"
end
