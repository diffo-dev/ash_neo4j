# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT
defmodule AshNeo4j.Test.Resource.Calculation.Href do
  use Ash.Resource.Calculation
  @moduledoc false

  @impl true
  def load(_query, _opts, _context), do: [:specification]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      case record.specification do
        %{tmf_version: tmf_version, type: type, name: name} ->
          "serviceInventoryManagement/v#{tmf_version}/#{type}/#{name}/#{record.id}"

        _ ->
          nil
      end
    end)
  end
end
