# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Resource.UpsertPlace do
  @moduledoc false

  # Upsert resource that extends the BasePlace fragment (label :Place) — the #392
  # regression case. A node created through the upsert? MERGE path must carry the
  # :Place fragment label, exactly as a plain create writes via all_labels.
  use Ash.Resource,
    domain: AshNeo4j.Test.SRM,
    fragments: [AshNeo4j.Test.Resource.BasePlace]

  actions do
    default_accept :*
    defaults [:read, :destroy]

    create :create do
      accept [:name, :field]
      upsert? true
      upsert_identity :unique_name
    end
  end

  attributes do
    attribute :name, :string, public?: true, primary_key?: true, allow_nil?: false
    attribute :field, :string, public?: true
  end

  identities do
    identity :unique_name, [:name]
  end
end
