# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Fragment.TestDomain do
  @moduledoc false

  # Domain fragment that contributes a :MyTestDomain label to any domain that
  # uses it. Exercises AshNeo4j.DataLayer.Domain and the domain fragment label
  # path in PersistLabels.
  use Spark.Dsl.Fragment,
    of: Ash.Domain,
    extensions: [AshNeo4j.DataLayer.Domain]

  neo4j do
    label :MyTestDomain
  end
end
