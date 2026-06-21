# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Unknown do
  @moduledoc """
  A sentinel value for *"the data layer tried to determine this and couldn't, in
  its current view of the graph"* — complementary to `Ash.NotLoaded`.

  `Ash.NotLoaded` marks a value that simply hasn't been fetched **yet** — ask
  again and it resolves. `AshNeo4j.Unknown` marks a value the read genuinely
  reached for and could **not** determine — e.g. a reached node whose labels
  don't resolve to a known resource, or a value a future store reports as
  indeterminate. Both are explicit values: consumers pattern-match `Unknown`,
  `nil`, and concrete values as distinct outcomes, and never read `nil`-meaning-
  absent into an `Unknown`.

  It deliberately implements no `String.Chars`/`Inspect`-coercion that would let
  it pass quietly as a value — use it where a value is expected and it stays
  loud; acknowledge it and it's calm.

  ## Shape

      %AshNeo4j.Unknown{
        world:   MyApp.SomeResource,   # the (Domain, Resource) frame of the original query
        reason:  :reached_unresolved,  # a leaf atom, OR a nested unknown from a deeper layer
        context: %{label: :Foo, …}     # local diagnostics, not load-bearing
      }

  * `:world` — the **(Domain, Resource) frame the query was asked in**, stored as
    the resource module (the Domain is derivable via `Ash.Resource.Info.domain/1`).
    It is the frame the caller is standing in — *not* the thing that failed to
    resolve (that belongs in `:reason`/`:context`). The Domain alone is
    insufficient: within one Domain multiple resources can share a base label,
    so Domain + Resource together identify the frame.

  * `:reason` — **either a leaf `atom()` or a nested unknown** from the layer
    beneath. The cause of not-knowing can *be* a deeper not-knowing: an
    `AshNeo4j.Unknown` raised at the data-layer boundary can carry, as its
    reason, a store's own indeterminate value, and an outer world (e.g. a
    consumer's `Diffo.Unknown`) can in turn carry this one. Outer holds inner
    **by value**, following the dependency direction — no module coupling, no
    cycles. The chain bottoms out in an atom. The atom vocabulary is
    library-structural and documented where each Unknown is produced; there is
    no central registry.

  * `:context` — `term()`, local diagnostics for *this* layer (the unresolved
    label, the hop chain, …). Never the place the cause lives.

  ## Frame-lifting at the boundary

  ash_neo4j is the layer that turns a frameless or store-native unknown into an
  Ash-framed one: it stamps `:world` with the resource being read and, where the
  unknown originated beneath it, carries that inner unknown as `:reason`. A store
  has no concept of a Domain/Resource pair, so its `:world` may be store-native
  or absent — this struct never assumes the thing it nests shares its notion of
  a world.
  """

  defstruct [:world, :reason, :context]

  @type t :: %__MODULE__{
          world: module() | nil,
          reason: atom() | struct(),
          context: term()
        }

  @doc """
  Builds an `AshNeo4j.Unknown` stamped with the query `world` (the resource the
  read was asked in), a `reason` (a leaf atom or a nested unknown), and optional
  local `context`.
  """
  @spec new(module() | nil, atom() | struct(), term()) :: t()
  def new(world, reason, context \\ %{}) do
    %__MODULE__{world: world, reason: reason, context: context}
  end

  @doc "True for an `AshNeo4j.Unknown`, false for anything else."
  @spec unknown?(term()) :: boolean()
  def unknown?(%__MODULE__{}), do: true
  def unknown?(_), do: false

  @doc """
  The Ash Domain of the query frame, derived from `:world` via
  `Ash.Resource.Info.domain/1`. `nil` when there is no resolvable world.
  """
  @spec domain(t()) :: module() | nil
  def domain(%__MODULE__{world: world}) when is_atom(world) and not is_nil(world) do
    Ash.Resource.Info.domain(world)
  end

  def domain(%__MODULE__{}), do: nil

  @doc """
  Walks the nested `:reason` chain to its leaf — the root-cause atom (or, if a
  nested unknown bottoms out in a non-atom, that value). For a single-layer
  Unknown this is just its `:reason`.
  """
  @spec root_reason(t()) :: term()
  def root_reason(%__MODULE__{reason: reason}), do: do_root_reason(reason)

  defp do_root_reason(%{reason: inner} = nested) when is_struct(nested), do: do_root_reason(inner)
  defp do_root_reason(reason), do: reason

  @doc """
  The stack of `:world` frames the unknown passed through, outermost first —
  one entry per nested unknown layer that carries a world. Layers without a
  world (e.g. a store-native leaf) contribute nothing.
  """
  @spec world_chain(t()) :: [module()]
  def world_chain(%__MODULE__{world: world, reason: reason}) do
    worlds = do_world_chain(reason)
    if is_nil(world), do: worlds, else: [world | worlds]
  end

  defp do_world_chain(%{world: world, reason: reason} = nested) when is_struct(nested) do
    rest = do_world_chain(reason)
    if is_nil(world), do: rest, else: [world | rest]
  end

  defp do_world_chain(_), do: []
end
