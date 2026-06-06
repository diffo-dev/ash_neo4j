# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Error.RequiresCypher25 do
  @moduledoc """
  Raised when a Cypher 25 operation is attempted against a Neo4j server older
  than 2025.06. Upgrade to Neo4j 2025.06 or later to use this feature.
  """
  defexception message: "This operation requires Cypher 25 (Neo4j ≥ 2025.06)"
end
