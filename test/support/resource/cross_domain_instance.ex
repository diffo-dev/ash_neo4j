# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Resource.CrossDomainInstance do
  @moduledoc false

  # Resource in SRM domain that extends CrossDomainBase, whose belongs_to target
  # (Blueprint) lives in the Provider domain. Exercises cross-domain enrichment.
  use Ash.Resource,
    domain: AshNeo4j.Test.SRM,
    fragments: [AshNeo4j.Test.Resource.CrossDomainBase]
end
