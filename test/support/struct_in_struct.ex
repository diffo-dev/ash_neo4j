# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.StructInStruct do
  @moduledoc false
  alias AshNeo4j.Test.Struct

  @derive Jason.Encoder
  defstruct struct: struct(Struct)
end
