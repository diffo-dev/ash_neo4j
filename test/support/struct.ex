# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Struct do
  @moduledoc false

  @derive Jason.Encoder
  defstruct a: :a, b: false, d: Decimal.new("4.2"), f: 1.2, i: 0, n: nil, s: "Hello"
end
