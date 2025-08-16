defmodule AshNeo4j.Test.StructInStruct do
  @moduledoc false
  alias AshNeo4j.Test.Struct

  defstruct struct: struct(Struct)

  defimpl String.Chars do
    def to_string(value) do
      inspect(value)
    end
  end
end
