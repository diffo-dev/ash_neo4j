defmodule Node.Post do
  use Ex4j.Node

  graph do
    field(:title, :string)
    field(:score, :integer)
    field(:public, :boolean)
    field(:unique, :string)
  end
end
