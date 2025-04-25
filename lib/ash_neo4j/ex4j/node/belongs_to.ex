defmodule Node.BELONGS_TO do
  use Ex4j.Node

  graph do
    field(:established, :utc_datetime_usec)
  end
end
