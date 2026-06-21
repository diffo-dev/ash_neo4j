# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Verifiers.VerifyIdentities do
  @moduledoc """
  Refuses, at compile time, any `identity` that can't be enforced as a Neo4j
  uniqueness constraint (#20) — so an unenforceable identity is caught loudly here
  rather than silently leaving a gap that permits duplicate/split records.

  Neo4j's `REQUIRE … IS UNIQUE` can't express two identity options:

    * `nils_distinct?: false` — Neo4j treats `nil`s as distinct and can't be made
      to treat them as equal.
    * a **filtered** identity (`where:`) — there is no partial/filtered constraint.

  The runtime counterpart is `AshNeo4j.Error.UnsupportedIdentity`, returned by
  `AshNeo4j.Constraint` for the same cases.
  """
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl) do
    resource = Verifier.get_persisted(dsl, :module)

    dsl
    |> Verifier.get_entities([:identities])
    |> Enum.find_value(:ok, fn identity ->
      cond do
        identity.where != nil ->
          refuse(resource, identity, "filtered identities (`where:`)")

        identity.nils_distinct? == false ->
          refuse(resource, identity, "identities with `nils_distinct?: false`")

        true ->
          nil
      end
    end)
  end

  # Framed in Ash terms (resource, identity, attributes, identity options); the
  # graph reason lives in the moduledoc, not in what the resource author sees.
  defp refuse(resource, identity, unsupported) do
    {:error,
     DslError.exception(
       module: resource,
       path: [:identities, identity.name],
       message:
         "cannot enforce uniqueness for identity :#{identity.name} (#{inspect(identity.keys)}) — " <>
           "the AshNeo4j data layer doesn't support #{unsupported}. Drop the unsupported option, " <>
           "or enforce that identity another way (#20)."
     )}
  end
end
