# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Constraint do
  @moduledoc """
  Convenience helpers for creating the Neo4j uniqueness constraints that enforce a
  resource's **primary key** (#32) and its `identities` (#20) at the database level.

      # Create the constraints for a resource (primary key + every identity)
      AshNeo4j.Constraint.create_constraints(AssignmentRelationship)

      # Review the Cypher without touching the database
      AshNeo4j.Constraint.constraint_statements(AssignmentRelationship)

  The primary-key constraint enforces uniqueness of the primary key among nodes of
  the resource's label. It's skipped when an identity already constrains the same
  attributes (no redundant constraint).

  Consistent with AshNeo4j's "no automatic migrations" stance — like
  `AshNeo4j.Vector`, this is an ergonomic tool you call (e.g. from a start-up or
  release task), not run on boot. Statements use `IF NOT EXISTS`, so they are safe
  to run repeatedly.

  ## Unsupported identities are refused, not skipped

  An identity that can't be enforced — `nils_distinct?: false`, or a filtered
  identity (`where:`) — returns `{:error, %AshNeo4j.Error.UnsupportedIdentity{}}`
  and creates **nothing** for the resource (all-or-nothing). Skipping would leave
  the identity unenforced and permit the duplicate records the constraint exists to
  prevent. The same cases are refused at compile time by
  `AshNeo4j.Verifiers.VerifyIdentities`.

  ## Naming

  Identity constraints are named `<label_lower>_<identity_name>` (e.g.
  `assignmentrelationship_unique_assignment`); the primary-key constraint is
  `<label_lower>_pk`.
  """

  alias AshNeo4j.Cypher
  alias AshNeo4j.Error.UnsupportedIdentity
  alias AshNeo4j.Resource.Info, as: ResourceInfo

  @doc """
  Runs `CREATE CONSTRAINT … IF NOT EXISTS` for `resource`'s primary key and every
  identity.

  Returns `{:ok, [%Bolty.Response{}]}` (one per constraint), or
  `{:error, %AshNeo4j.Error.UnsupportedIdentity{}}` if any identity can't be
  enforced — in which case nothing is created.
  """
  @spec create_constraints(Ash.Resource.t(), keyword()) ::
          {:ok, [Bolty.Response.t()]} | {:error, term()}
  def create_constraints(resource, _opts \\ []) do
    with {:ok, specs} <- specs(resource) do
      run_all(Enum.map(specs, &create_cypher/1))
    end
  end

  @doc """
  Runs `DROP CONSTRAINT … IF EXISTS` for `resource`'s primary key and every identity.
  A no-op for absent constraints. Unsupported identities are refused (nothing was
  created for them to drop), consistent with `create_constraints/2`.
  """
  @spec drop_constraints(Ash.Resource.t(), keyword()) ::
          {:ok, [Bolty.Response.t()]} | {:error, term()}
  def drop_constraints(resource, _opts \\ []) do
    with {:ok, specs} <- specs(resource) do
      run_all(Enum.map(specs, &drop_cypher/1))
    end
  end

  @doc """
  Returns `{:ok, [statement]}` — the `CREATE CONSTRAINT` Cypher `create_constraints/2`
  would run — without touching the database, or `{:error, %UnsupportedIdentity{}}`.

      AshNeo4j.Constraint.constraint_statements(Post)
      #=> {:ok, ["CREATE CONSTRAINT post_pk IF NOT EXISTS FOR (n:Post) REQUIRE n.uuid IS UNIQUE",
      #         "CREATE CONSTRAINT post_unique_unique IF NOT EXISTS FOR (n:Post) REQUIRE n.unique IS UNIQUE"]}
  """
  @spec constraint_statements(Ash.Resource.t()) :: {:ok, [String.t()]} | {:error, term()}
  def constraint_statements(resource) do
    with {:ok, specs} <- specs(resource), do: {:ok, Enum.map(specs, &create_cypher/1)}
  end

  # --- resolution --------------------------------------------------------

  # Resolves every identity to a constraint spec, or refuses the first one that
  # can't be enforced (all-or-nothing).
  defp specs(resource) do
    label = ResourceInfo.module_label(resource)
    translations = ResourceInfo.translations(resource)

    with {:ok, identity_specs} <- identity_specs(resource, label, translations) do
      {:ok, primary_key_spec(resource, label, translations, identity_specs) ++ identity_specs}
    end
  end

  defp identity_specs(resource, label, translations) do
    Enum.reduce_while(Ash.Resource.Info.identities(resource), {:ok, []}, fn identity, {:ok, acc} ->
      case spec(resource, label, translations, identity) do
        {:ok, spec} -> {:cont, {:ok, [spec | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, specs} -> {:ok, Enum.reverse(specs)}
      error -> error
    end
  end

  # The primary-key uniqueness constraint (#32). Skipped when an identity already
  # constrains the same property set (no redundant constraint). Always enforceable:
  # primary-key attributes are required, so the `nils_distinct?`/`where` limits
  # never apply.
  defp primary_key_spec(resource, label, translations, identity_specs) do
    case Ash.Resource.Info.primary_key(resource) do
      [] ->
        []

      keys ->
        properties = properties_for(keys, translations)

        if Enum.any?(identity_specs, &(MapSet.new(&1.properties) == MapSet.new(properties))) do
          []
        else
          [%{name: constraint_name(label, "pk"), label: label, properties: properties}]
        end
    end
  end

  defp spec(resource, _label, _translations, %{where: where} = identity) when where != nil do
    {:error, UnsupportedIdentity.exception(resource: resource, identity: identity.name, keys: identity.keys, reason: :filtered)}
  end

  defp spec(resource, _label, _translations, %{nils_distinct?: false} = identity) do
    {:error,
     UnsupportedIdentity.exception(resource: resource, identity: identity.name, keys: identity.keys, reason: :nils_not_distinct)}
  end

  defp spec(_resource, label, translations, identity) do
    {:ok,
     %{
       name: constraint_name(label, identity.name),
       label: label,
       properties: properties_for(identity.keys, translations)
     }}
  end

  defp properties_for(keys, translations), do: Enum.map(keys, &to_string(Keyword.get(translations, &1, &1)))

  defp constraint_name(label, suffix), do: "#{label |> to_string() |> String.downcase()}_#{suffix}"

  # --- cypher ------------------------------------------------------------

  defp create_cypher(%{name: name, label: label, properties: properties}) do
    "CREATE CONSTRAINT #{name} IF NOT EXISTS FOR (n:#{label}) REQUIRE #{require_clause(properties)} IS UNIQUE"
  end

  defp drop_cypher(%{name: name}), do: "DROP CONSTRAINT #{name} IF EXISTS"

  defp require_clause([property]), do: "n.#{property}"
  defp require_clause(properties), do: "(" <> Enum.map_join(properties, ", ", &"n.#{&1}") <> ")"

  defp run_all(statements) do
    Enum.reduce_while(statements, {:ok, []}, fn cypher, {:ok, acc} ->
      case Cypher.run(cypher) do
        {:ok, response} -> {:cont, {:ok, [response | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, responses} -> {:ok, Enum.reverse(responses)}
      error -> error
    end
  end
end
