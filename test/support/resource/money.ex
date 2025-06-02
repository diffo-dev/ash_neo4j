defmodule AshNeo4j.Test.Resource.Money do
  @moduledoc false
  use Ash.Resource,
    data_layer: :embedded

  attributes do
    attribute :amount, :integer do
      public? true
      allow_nil? false
      # constraints min: 0
    end

    attribute :currency, :atom do
      public? true
      allow_nil? false
      # constraints one_of: [:aud, :eur, :sek, :usd]
    end
  end

  defimpl String.Chars do
    def to_string(v) do
      "%AshNeo4j.Test.Resource.Money{amount: #{v.amount}, currency: :#{v.currency}}"
    end
  end
end
