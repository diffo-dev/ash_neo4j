defmodule AshNeo4j.Test.Resource.StateMachine do
  @moduledoc false
  use Ash.Resource,
    domain: AshNeo4j.Test.Domain,
    extensions: [AshStateMachine],
    data_layer: AshNeo4j.DataLayer

  state_machine do
    initial_states([:initial])
    state_attribute(:operational_state)

    transitions do
      transition(:start, from: :initial, to: [:started])
      transition(:stop, from: :started, to: [:stopped])
    end
  end

  neo4j do
    translate id: :uuid
  end

  actions do
    defaults [:create, :read, :destroy]

    update :start do
      change transition_state(:started)
    end

    update :stop do
      change transition_state(:stopped)
    end
  end

  attributes do
    uuid_primary_key :id, writable?: true

    # attribute :operational_state, :atom do
    #  allow_nil? false
    #  default :initial
    #  public? true
    #  constraints one_of: [:initial, :started, :stopped]
    # end
  end
end
