# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Resource.Money do
  @moduledoc false
  use Ash.Resource,
    data_layer: :embedded

  attributes do
    attribute :amount, :integer do
      public? true
      allow_nil? false
      constraints min: 0
    end

    attribute :currency, :atom do
      public? true
      allow_nil? false
      constraints one_of: [:aud, :eur, :sek, :usd]
    end
  end
end
