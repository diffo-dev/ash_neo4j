# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Provider do
  @moduledoc false
  use Ash.Domain, fragments: [AshNeo4j.Test.Fragment.TestDomain]

  resources do
    allow_unregistered? true
  end
end
