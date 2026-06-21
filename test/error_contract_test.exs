# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.ErrorContractTest do
  @moduledoc """
  Guards the data-layer error contract (#372): the behaviour modules must never
  return a bare-string `{:error, "…"}`. Every error the data layer surfaces is a
  typed struct — an `AshNeo4j.Error.*` (e.g. `Internal`, `Neo4j`, `Unsupported*`)
  or a reused Ash error (`StaleRecord`, `Unavailable`, …) — so it carries a `class`
  and structured fields and is pattern-matchable. A bare string becomes
  `Ash.Error.Unknown.UnknownError` (unclassified, only substring-matchable).

  Internal sentinels between helpers (e.g. `{:error, :nothing_deleted}`) are atoms,
  not strings, and never escape to Ash.

  `Ash.Type` callback modules (`data_layer/cast.ex`, `data_layer/dump.ex`,
  `util.ex`, `type/*`, `vector.ex`, `spatial.ex`) are **deliberately excluded** —
  type callbacks follow Ash's type-error convention (message strings / `:error`),
  which is a different contract from the data-layer behaviour callbacks.
  """
  use ExUnit.Case, async: true

  # The data-layer behaviour callbacks and their direct helpers — the surface whose
  # `{:error, _}` is returned to Ash and classified by `class`.
  @behaviour_modules ~w(
    lib/data_layer.ex
    lib/neo4j_helper.ex
    lib/cypher.ex
    lib/query_helper.ex
  )

  test "behaviour modules never return a bare-string {:error, \"…\"}" do
    offenders =
      for path <- @behaviour_modules,
          {line, idx} <- Enum.with_index(String.split(File.read!(path), "\n"), 1),
          String.match?(line, ~r/\{:error,\s*"/),
          do: "#{path}:#{idx}: #{String.trim(line)}"

    assert offenders == [],
           "Found bare-string error return(s) in behaviour modules — use a typed " <>
             "AshNeo4j.Error.* or a reused Ash error instead (#372):\n" <>
             Enum.join(offenders, "\n")
  end
end
