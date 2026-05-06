# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Test.Resource.Calculation.Version do
  use Ash.Resource.Calculation
  @moduledoc false

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn r ->
      "v#{r.major_version}.#{r.minor_version}.#{r.patch_version}"
    end)
  end
end
