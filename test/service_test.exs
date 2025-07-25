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
      assert refreshed_latest_specification.version == "v2.0.0"
    end

    test "service can calculate href using referenced specification" do
      broadband_v1 = Specification |> Ash.create!(%{name: "broadband"})
      service = Service |> Ash.create!(%{name: "broadband_0000", specified_by: broadband_v1.id})
      {:ok, refreshed_service} = service |> Ash.load(:href)
      assert refreshed_service.href == "serviceInventoryManagement/v4/service/broadband/#{service.id}"
    end
  end

  describe "ash create action tests" do
    test "service node can be created with a single relationship" do
      broadband_v1 = Specification |> Ash.create!(%{name: "broadband"})
      service = Service |> Ash.create!(%{name: "broadband_0000", specified_by: broadband_v1.id})

      assert service.specification.id == broadband_v1.id
    end

    test "resource node can be created with multiple relationships" do
      broadband_v1 = Specification |> Ash.create!(%{name: "broadband"})
      service = Service |> Ash.create!(%{name: "broadband_0000", specified_by: broadband_v1.id})
      esim_v1 = Specification |> Ash.create!(%{name: "esim", type: :resource})

      resource =
        Resource
        |> Ash.create!(%{name: "esim_0000", specified_by: esim_v1.id, used_by_service: service.id})

      # |> IO.inspect(label: :resource)

      assert is_struct(resource.specification, Specification)
      assert is_struct(resource.service, Service)
      assert resource.specification_id == esim_v1.id
      assert resource.service_id == service.id
    end

    test "find a service by specification id, checking resource enrichment" do
      broadband_v1 = Specification |> Ash.create!(%{name: "broadband"})
      service1 = Service |> Ash.create!(%{name: "broadband_0001", specified_by: broadband_v1.id})
      broadband_v2 = Specification |> Ash.create!(%{name: "broadband", major_version: 2})
      service2 = Service |> Ash.create!(%{name: "broadband_0002", specified_by: broadband_v2.id})
      esim_v1 = Specification |> Ash.create!(%{name: "esim", type: :resource})

      _resource1 =
        Resource
        |> Ash.create!(%{name: "esim_0001", specified_by: esim_v1.id, used_by_service: service1.id})

      resource2 =
        Resource
        |> Ash.create!(%{name: "esim_0002", specified_by: esim_v1.id, used_by_service: service2.id})

      found_service =
        Service
        |> Ash.Query.for_read(:read)
        |> Ash.Query.filter(specification_id: broadband_v2.id)
        |> Ash.read_one!()

      # check enrichment
      assert is_struct(found_service.specification, Specification)
      assert found_service.specification_id == broadband_v2.id

      refute is_struct(found_service.resources, Ash.NotLoaded)
      assert length(found_service.resources) == 1
      found_resource = hd(found_service.resources)
      assert is_struct(found_resource, Resource)
      assert found_resource.id == resource2.id
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
      {:ok, service_specification} = Specification |> Ash.create(%{name: "service specification"})
      {:ok, resource_specification} = Specification |> Ash.create(%{name: "resource specification", type: :resource})

      {:ok, parent_service} =
        Service
        |> Ash.Changeset.for_create(:create, %{name: "parent_service", specified_by: service_specification.id})
        |> Ash.create()

      {:ok, child_service} =
        Service
        |> Ash.Changeset.for_create(:create, %{name: "child_service", specified_by: service_specification.id})
        |> Ash.create()

      {:ok, _related_parent_service} =
        parent_service |> Ash.Changeset.for_update(:update, manage_services: [child_service.id]) |> Ash.update()

      {:ok, parent_resource} =
        Resource
        |> Ash.Changeset.for_create(:create, %{name: "parent_resource", specified_by: resource_specification.id})
        |> Ash.create()

      {:ok, _related_child_service} =
        child_service |> Ash.Changeset.for_update(:update, use_resources: [parent_resource.id]) |> Ash.update()

      {:ok, child_resource} =
        Resource
        |> Ash.Changeset.for_create(:create, %{name: "child_resource", specified_by: resource_specification.id})
        |> Ash.create()

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

  describe "ash destroy action tests" do
    test "unused specification node can be destroyed" do
      {:ok, service_specification} = Specification |> Ash.create(%{name: "service specification"})
      :ok = service_specification |> Ash.destroy()
    end

    test "service can be destroyed" do
      {:ok, service_specification} = Specification |> Ash.create(%{name: "service specification"})
      {:ok, service} = Service |> Ash.create(%{name: "service", specified_by: service_specification.id})
      :ok = service |> Ash.destroy()
    end

    test "resource can be destroyed" do
      {:ok, resource_specification} = Specification |> Ash.create(%{name: "resource specification", type: :resource})
      {:ok, resource} = Resource |> Ash.create(%{name: "resource", specified_by: resource_specification.id})
      :ok = resource |> Ash.destroy()
    end

    test "specification cannot be destroyed when used by a service" do
      {:ok, service_specification} = Specification |> Ash.create(%{name: "service specification"})
      {:ok, service} = Service |> Ash.create(%{name: "service", specified_by: service_specification.id})
      {:error, error} = service_specification |> Ash.destroy()
      assert is_struct(error, Ash.Error.Invalid)
      :ok = service |> Ash.destroy()
      :ok = service_specification |> Ash.destroy()
    end

    test "specification cannot be destroyed when used by a resource" do
      {:ok, resource_specification} = Specification |> Ash.create(%{name: "resource specification", type: :resource})
      {:ok, resource} = Resource |> Ash.create(%{name: "resource", specified_by: resource_specification.id})
      {:error, error} = resource_specification |> Ash.destroy() |> IO.inspect()
      assert is_struct(error, Ash.Error.Invalid)
      :ok = resource |> Ash.destroy()
      :ok = resource_specification |> Ash.destroy()
    end
  end

  describe "has one relationship tests" do
    test "(InternalService) -[FIRED]-> (Event)" do
      {:ok, service_specification} = Specification |> Ash.create(%{name: "service specification"})
      {:ok, service} = Service |> Ash.create(%{name: "service", specified_by: service_specification.id})
      {:ok, event} = Event |> Ash.create(%{type: :create})
      {:ok, updated_service} = service |> Ash.update(%{fire_event: event.id})
      assert is_struct(updated_service, Service)
      assert updated_service.event.id == event.id
      assert is_struct(updated_service.event, Event)

      {:ok, refreshed_event} = event |> Ash.reload()
      assert is_struct(refreshed_event, Event)
      assert refreshed_event.service_id == service.id
      refute refreshed_event.resource_id
      assert is_struct(refreshed_event.service, Ash.NotLoaded)
      assert is_struct(refreshed_event.resource, Ash.NotLoaded)

      assert Neo4jHelper.nodes_relate_how?(
               :InternalService,
               %{name: "service"},
               :Event,
               %{type: :create},
               :FIRED,
               :outgoing
             )
    end

    test "(InternalResource) -[FIRED]-> (Event)" do
      {:ok, resource_specification} = Specification |> Ash.create(%{name: "resource specification", type: :resource})
      {:ok, resource} = Resource |> Ash.create(%{name: "resource", specified_by: resource_specification.id})
      {:ok, event} = Event |> Ash.create(%{type: :create})
      {:ok, updated_resource} = resource |> Ash.update(%{fire_event: event.id})
      assert is_struct(updated_resource, Resource)
      assert updated_resource.event.id == event.id
      assert is_struct(updated_resource.event, Event)

      {:ok, refreshed_event} = event |> Ash.reload()
      assert is_struct(refreshed_event, Event)
      refute refreshed_event.service_id
      assert refreshed_event.resource_id == resource.id
      assert is_struct(refreshed_event.service, Ash.NotLoaded)
      assert is_struct(refreshed_event.resource, Ash.NotLoaded)

      assert Neo4jHelper.nodes_relate_how?(
               :InternalResource,
               %{name: "resource"},
               :Event,
               %{type: :create},
               :FIRED,
               :outgoing
             )
    end

    test "(Event) -[AFTER]-> (Event)" do
      {:ok, create_event} = Event |> Ash.create(%{type: :create})
      refute create_event.event_id
      assert is_struct(create_event.previous_event, Ash.NotLoaded)
      {:ok, activate_event} = Event |> Ash.create(%{type: :activate})
      {:ok, updated_activate_event} = activate_event |> Ash.update(%{previous_event: create_event.id})
      assert is_struct(updated_activate_event, Event)
      refute updated_activate_event.event_id
      assert is_struct(updated_activate_event.previous_event, Event)

      # the create event should not have a previous event
      {:ok, refreshed_create_event} = create_event |> Ash.reload()
      assert is_struct(refreshed_create_event, Event)
      refute refreshed_create_event.event_id
      refute refreshed_create_event.previous_event

      assert Neo4jHelper.nodes_relate_how?(
               :Event,
               %{type: :activate},
               :Event,
               %{type: :create},
               :AFTER,
               :outgoing
             )
    end
  end
end
