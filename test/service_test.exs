defmodule AshNeo4j.Service.Test do
  @moduledoc false
  use ExUnit.Case, async: false
  alias AshNeo4j.Neo4jHelper
  alias AshNeo4j.BoltxHelper
  alias AshNeo4j.Test.Resource.Specification
  alias AshNeo4j.Test.Resource.Service
  alias AshNeo4j.Test.Resource.Resource
  alias AshNeo4j.Test.Resource.Event
  require Ash.Query

  setup_all do
    BoltxHelper.start()
  end

  setup do
    on_exit(fn ->
      Neo4jHelper.delete_nodes(:InternalService)
      Neo4jHelper.delete_nodes(:InternalResource)
      Neo4jHelper.delete_nodes(:Specification)
      Neo4jHelper.delete_nodes(:Event)
    end)
  end

  describe "Boltx configuration tests" do
    test "neo4j is running" do
      assert BoltxHelper.is_connected()
    end
  end

  describe "ash read action tests" do
    test "find the latest specification with a given name" do
      _access_v1 = Specification |> Ash.create!(%{name: "access", major_version: 1})
      _access_v2 = Specification |> Ash.create!(%{name: "access", major_version: 2})
      _edge_v3 = Specification |> Ash.create!(%{name: "edge", major_version: 3})

      latest_specification = Specification |> Ash.Query.for_read(:get_latest, %{query: "access"}) |> Ash.read_one!()
      assert latest_specification
      assert latest_specification.major_version == 2
      assert latest_specification.name == "access"
      {:ok, refreshed_latest_specification} = latest_specification |> Ash.load(:version)
      assert refreshed_latest_specification.version == "v2.0"
    end
  end

  describe "ash update action tests" do
    test "resource node can be created and related to a specification using ash create" do
      esim_v1 = Specification |> Ash.create!(%{name: "esim", type: :resource})
      resource = Resource |> Ash.create!(%{name: "esim_0000", specified_by: esim_v1.id})

      assert resource.specification.id == esim_v1.id
    end

    test "service node can be created and related to a specification using ash create" do
      broadband_v1 = Specification |> Ash.create!(%{name: "broadband"})
      service = Service |> Ash.create!(%{name: "broadband_0000", specified_by: broadband_v1.id})

      assert service.specification.id == broadband_v1.id
    end

    test "service-service-resource-resource relationships using ash" do
      {:ok, parent_service} = Service |> Ash.Changeset.for_create(:create, %{name: "parent_service"}) |> Ash.create()
      {:ok, child_service} = Service |> Ash.Changeset.for_create(:create, %{name: "child_service"}) |> Ash.create()

      {:ok, _related_parent_service} =
        parent_service |> Ash.Changeset.for_update(:update, manage_services: [child_service.id]) |> Ash.update()

      {:ok, parent_resource} = Resource |> Ash.Changeset.for_create(:create, %{name: "parent_resource"}) |> Ash.create()

      {:ok, _related_child_service} =
        child_service |> Ash.Changeset.for_update(:update, use_resources: [parent_resource.id]) |> Ash.update()

      {:ok, child_resource} = Resource |> Ash.Changeset.for_create(:create, %{name: "child_resource"}) |> Ash.create()

      {:ok, _related_parent_resource} =
        parent_resource |> Ash.Changeset.for_update(:update, use_resources: [child_resource.id]) |> Ash.update()

      assert Neo4jHelper.nodes_relate_how?(
               :InternalService,
               %{name: "parent_service"},
               :InternalService,
               %{name: "child_service"},
               :MANAGES,
               :outgoing
             )

      assert Neo4jHelper.nodes_relate_how?(
               :InternalService,
               %{name: "child_service"},
               :InternalResource,
               %{name: "parent_resource"},
               :USES,
               :outgoing
             )

      assert Neo4jHelper.nodes_relate_how?(
               :InternalResource,
               %{name: "parent_resource"},
               :InternalResource,
               %{name: "child_resource"},
               :USES,
               :outgoing
             )
    end
  end

  describe "has one relationship tests" do
    test "(InternalService) -[FIRED]-> (Event)" do
      {:ok, service} = Service |> Ash.create(%{name: "service"})
      {:ok, event} = Event |> Ash.create(%{type: :create})
      {:ok, updated_service} = service |> Ash.update(%{fire_event: event.id})
      {:ok, refreshed_event} = event |> Ash.load(:service_id)

      assert Neo4jHelper.nodes_relate_how?(
               :InternalService,
               %{name: "service"},
               :Event,
               %{type: :create},
               :FIRED,
               :outgoing
             )

      assert updated_service.event.id == event.id
      assert refreshed_event.service_id == service.id
    end

    test "(InternalResource) -[FIRED]-> (Event)" do
      {:ok, resource} = Resource |> Ash.create(%{name: "resource"})
      {:ok, event} = Event |> Ash.create(%{type: :create})
      {:ok, updated_resource} = resource |> Ash.update(%{fire_event: event.id})
      {:ok, refreshed_event} = event |> Ash.load(:resource_id)

      assert Neo4jHelper.nodes_relate_how?(
               :InternalResource,
               %{name: "resource"},
               :Event,
               %{type: :create},
               :FIRED,
               :outgoing
             )

      assert updated_resource.event.id == event.id
      assert refreshed_event.resource_id == resource.id
    end

    test "(Event) -[AFTER]-> (Event)" do
      {:ok, create_event} = Event |> Ash.create(%{type: :create})
      {:ok, activate_event} = Event |> Ash.create(%{type: :activate})
      {:ok, updated_activate_event} = activate_event |> Ash.update(%{earlier_event: create_event.id})
      {:ok, refreshed_create_event} = create_event |> Ash.load(:event_id)

      assert Neo4jHelper.nodes_relate_how?(
               :Event,
               %{type: :activate},
               :Event,
               %{type: :create},
               :AFTER,
               :outgoing
             )


      assert updated_activate_event.event.id == create_event.id
      refute is_struct(updated_activate_event.event, Ash.NotLoaded)
      refute refreshed_create_event.event_id
      assert is_struct(refreshed_create_event.event, Ash.NotLoaded)
    end
  end
end
