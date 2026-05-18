# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.FragmentTest do
  @moduledoc false
  use ExUnit.Case, async: true
  alias AshNeo4j.BoltyHelper
  alias AshNeo4j.Sandbox
  alias AshNeo4j.Test.Resource.Blueprint
  alias AshNeo4j.Test.Resource.CrossDomainInstance
  alias AshNeo4j.Test.Resource.NoiseInstance
  alias AshNeo4j.Test.Resource.Specification
  alias AshNeo4j.Test.Resource.TypedInstance

  setup_all do
    BoltyHelper.start()
  end

  setup do
    Sandbox.checkout()
    on_exit(&Sandbox.rollback/0)
  end

  describe "belongs_to enrichment from fragment" do
    test "specification_id is populated on read when belongs_to is declared on the fragment" do
      spec = Specification |> Ash.create!(%{name: "mySpec"})

      instance =
        TypedInstance
        |> Ash.create!(%{name: "instance_001", specified_by: spec.id})

      # Value is correct immediately after create
      assert instance.specification_id == spec.id

      # Reload via Ash.get — this is where the bug manifests
      reloaded = TypedInstance |> Ash.get!(instance.id)

      assert reloaded.specification_id == spec.id
    end

    test "specification_id is nil when no specification edge exists" do
      instance = TypedInstance |> Ash.create!(%{name: "instance_no_spec"})

      reloaded = TypedInstance |> Ash.get!(instance.id)

      assert reloaded.specification_id == nil
    end
  end

  describe "belongs_to enrichment across domain boundary" do
    test "blueprint_id is populated on read when belongs_to target is in a different domain" do
      blueprint = Blueprint |> Ash.create!(%{name: "myBlueprint"})

      instance =
        CrossDomainInstance
        |> Ash.create!(%{name: "cross_001", blueprinted_by: blueprint.id})

      assert instance.blueprint_id == blueprint.id

      reloaded = CrossDomainInstance |> Ash.get!(instance.id)

      assert reloaded.blueprint_id == blueprint.id
    end

    test "blueprint_id is nil when no blueprint edge exists" do
      instance = CrossDomainInstance |> Ash.create!(%{name: "cross_no_blueprint"})

      reloaded = CrossDomainInstance |> Ash.get!(instance.id)

      assert reloaded.blueprint_id == nil
    end
  end

  describe "label scoping with fragment noise" do
    test "Ash.read! returns only the target resource when a sibling fragment resource exists" do
      # Create a NoiseInstance — shares :CrossDomainType label with CrossDomainInstance.
      # If reads scope only by fragment label, this noise node will appear in
      # CrossDomainInstance reads, revealing the #257 label scoping bug.
      _noise = NoiseInstance |> Ash.create!(%{name: "noise_node"})

      blueprint = Blueprint |> Ash.create!(%{name: "scopingBlueprint"})
      instance = CrossDomainInstance |> Ash.create!(%{name: "scoped_001", blueprinted_by: blueprint.id})

      results = CrossDomainInstance |> Ash.read!()

      assert length(results) == 1
      assert hd(results).id == instance.id
      assert hd(results).blueprint_id == blueprint.id
    end

    test "Ash.get! populates blueprint_id even when sibling fragment nodes exist" do
      _noise = NoiseInstance |> Ash.create!(%{name: "noise_for_get"})

      blueprint = Blueprint |> Ash.create!(%{name: "getBlueprintNoise"})
      instance = CrossDomainInstance |> Ash.create!(%{name: "get_scoped", blueprinted_by: blueprint.id})

      reloaded = CrossDomainInstance |> Ash.get!(instance.id)

      assert reloaded.blueprint_id == blueprint.id
    end
  end
end
