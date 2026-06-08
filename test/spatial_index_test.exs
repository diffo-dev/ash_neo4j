# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.SpatialIndexTest do
  @moduledoc """
  `AshNeo4j.Spatial.index_statements/3` companion selection (dry run, no DB).

  A point-shaped attribute — 2D `:point` or 3D `:point_z` (#270) — indexes its
  single `.point` companion; an areal/linear geometry indexes `.bbSW`/`.bbNE`.
  The 3D case is the regression for #306: a `:point_z` attribute was being
  treated as a bbox geometry, so `create_index` built indexes on
  `<attr>.bbSW`/`.bbNE` (which a `%Geo.PointZ{}` never writes) instead of the
  `<attr>.point` it actually stores — leaving 3D distance queries unindexed.
  """
  use ExUnit.Case, async: true

  alias AshNeo4j.Spatial
  alias AshNeo4j.Test.Resource.Place

  test "3D point_z attribute indexes the .point companion, not bbSW/bbNE (#306)" do
    {:ok, [stmt]} = Spatial.index_statements(Place, :tower)
    assert stmt =~ "tower.point"
    refute stmt =~ "bbSW"
    refute stmt =~ "bbNE"
  end

  test "2D point attribute indexes the .point companion" do
    {:ok, [stmt]} = Spatial.index_statements(Place, :location)
    assert stmt =~ "location.point"
  end

  test "polygon attribute indexes the bbSW/bbNE companions" do
    {:ok, stmts} = Spatial.index_statements(Place, :bounds)
    assert Enum.any?(stmts, &(&1 =~ "bbSW"))
    assert Enum.any?(stmts, &(&1 =~ "bbNE"))
  end
end
