defmodule AshNeo4j.Test.Struct do
    @moduledoc false

    defstruct [a: :a, b: false, d: Decimal.new("4.2"), f: 1.2, i: 0, n: nil, s: "Hello"]
end
