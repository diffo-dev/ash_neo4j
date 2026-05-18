# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Resource.NoiseInstance do
  @moduledoc false

  # Second resource extending CrossDomainBase — used as "noise" to verify label
  # scoping: if reads use only the fragment label (:CrossDomainType), this
  # resource's nodes will appear in CrossDomainInstance reads and vice versa.
  use Ash.Resource,
    domain: AshNeo4j.Test.SRM,
    fragments: [AshNeo4j.Test.Resource.CrossDomainBase]
end
