# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.DataLayer.Domain.Info do
  @moduledoc "Introspection helpers for AshNeo4j.DataLayer.Domain"
  use Spark.InfoGenerator, extension: AshNeo4j.DataLayer.Domain, sections: [:neo4j]
end
