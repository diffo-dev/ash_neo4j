# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Cypher.Query do
  @moduledoc """
  Typed representation of a Cypher query.

  Build a query by constructing a list of clause structs and collecting parameters
  into the `params` map. Render to `{string, params}` via `AshNeo4j.Cypher.render/1`,
  or pass directly to `AshNeo4j.Cypher.run/1`.

  ## Clause structs

  - `AshNeo4j.Cypher.Match` — `MATCH <pattern>`
  - `AshNeo4j.Cypher.OptionalMatch` — `OPTIONAL MATCH <pattern>`
  - `AshNeo4j.Cypher.Where` — `WHERE cond1 AND cond2 ...`
  - `AshNeo4j.Cypher.With` — `WITH item1, item2 ...`
  - `AshNeo4j.Cypher.Return` — `RETURN item1, item2 ...`
  - `AshNeo4j.Cypher.OrderBy` — `ORDER BY prop ASC/DESC ...`
  - `AshNeo4j.Cypher.Skip` — `SKIP n`
  - `AshNeo4j.Cypher.Limit` — `LIMIT n`

  ## Example

      %Cypher.Query{
        clauses: [
          %Cypher.Match{pattern: "(s:Actor)"},
          %Cypher.Where{conditions: ["s.born > $year"]},
          %Cypher.Return{items: ["s"]},
          %Cypher.Limit{value: 10}
        ],
        params: %{"year" => 1970}
      }

  """

  @type clause ::
          AshNeo4j.Cypher.Match.t()
          | AshNeo4j.Cypher.OptionalMatch.t()
          | AshNeo4j.Cypher.Where.t()
          | AshNeo4j.Cypher.With.t()
          | AshNeo4j.Cypher.Return.t()
          | AshNeo4j.Cypher.OrderBy.t()
          | AshNeo4j.Cypher.Skip.t()
          | AshNeo4j.Cypher.Limit.t()

  @type t :: %__MODULE__{clauses: [clause()], params: map()}

  defstruct clauses: [], params: %{}
end

defmodule AshNeo4j.Cypher.Match do
  @moduledoc "MATCH clause. `pattern` is a Cypher pattern string, e.g. `\"(s:Actor)\"`."
  @type t :: %__MODULE__{pattern: String.t()}
  defstruct [:pattern]
end

defmodule AshNeo4j.Cypher.OptionalMatch do
  @moduledoc "OPTIONAL MATCH clause."
  @type t :: %__MODULE__{pattern: String.t()}
  defstruct [:pattern]
end

defmodule AshNeo4j.Cypher.Where do
  @moduledoc "WHERE clause. Each entry in `conditions` is ANDed together."
  @type t :: %__MODULE__{conditions: [String.t()]}
  defstruct conditions: []
end

defmodule AshNeo4j.Cypher.With do
  @moduledoc "WITH clause."
  @type t :: %__MODULE__{items: [String.t()]}
  defstruct items: []
end

defmodule AshNeo4j.Cypher.Return do
  @moduledoc "RETURN clause."
  @type t :: %__MODULE__{items: [String.t()]}
  defstruct items: []
end

defmodule AshNeo4j.Cypher.OrderBy do
  @moduledoc "ORDER BY clause. Each term is a `{property_expression, :asc | :desc}` pair."
  @type sort_term :: {String.t(), :asc | :desc}
  @type t :: %__MODULE__{terms: [sort_term()]}
  defstruct terms: []
end

defmodule AshNeo4j.Cypher.Skip do
  @moduledoc "SKIP clause."
  @type t :: %__MODULE__{value: non_neg_integer()}
  defstruct [:value]
end

defmodule AshNeo4j.Cypher.Limit do
  @moduledoc "LIMIT clause."
  @type t :: %__MODULE__{value: pos_integer()}
  defstruct [:value]
end
