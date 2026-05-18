# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/globals.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Resource.TypedInstance do
  @moduledoc false

  # Resource that extends BaseType fragment — mirrors a concrete Instance kind in diffo.
  use Ash.Resource,
    domain: AshNeo4j.Test.SRM,
    fragments: [AshNeo4j.Test.Resource.BaseType]
end
