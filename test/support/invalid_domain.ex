# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Invalid_Domain do
  @moduledoc false
  use Ash.Domain

  resources do
    allow_unregistered? true
  end
end
