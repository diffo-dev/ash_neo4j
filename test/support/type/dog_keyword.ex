# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Type.DogKeyword do
  @moduledoc false
  use Ash.Type.NewType,
    subtype_of: :keyword,
    constraints: [
      fields: [
        name: [
          type: :string,
          allow_nil?: false
        ],
        age: [
          type: :integer,
          constraints: [
            min: 0
          ]
        ],
        breed: [
          type: :atom
        ]
      ]
    ]
end
