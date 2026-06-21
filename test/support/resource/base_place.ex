# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Resource.BasePlace do
  @moduledoc false

  # Fragment that overrides the type label to :Place — mirrors the BaseInstance /
  # BasePlace pattern in diffo where every concrete leaf carries an abstract base
  # label on CREATE so reader resources can find and relate them (#392).
  use Spark.Dsl.Fragment,
    of: Ash.Resource,
    data_layer: AshNeo4j.DataLayer

  neo4j do
    label :Place
  end
end
