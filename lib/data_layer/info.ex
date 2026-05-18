# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.DataLayer.Info do
  @moduledoc "Introspection helpers for AshNeo4j.DataLayer"
  use Spark.InfoGenerator, extension: AshNeo4j.DataLayer, sections: [:neo4j]
end
