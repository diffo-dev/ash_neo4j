# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT
defmodule AshNeo4j.Test.Type.DogUnion do
  @moduledoc false
  use Ash.Type.NewType,
    subtype_of: :union,
    constraints: [
      types: [
        typed_struct: [
          type: AshNeo4j.Test.Type.DogTypedStruct,
          tag: :type,
          tag_value: :typed_struct
        ],
        tuple: [
          type: AshNeo4j.Test.Type.DogTuple,
          tag: :type,
          tag_value: :tuple
        ]
      ],
      storage: :type_and_value
    ]
end
