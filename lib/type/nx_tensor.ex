# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Type.NxTensor do
  @moduledoc """
  Ash attribute type for a rank-generic typed tensor (#309), backed by
  `Nx.Tensor`.

  The Elixir-side value is an `Nx.Tensor` — so the value-blind structural ops
  (`Nx.transpose/2` (lazy), `Nx.reshape/2`, `Nx.slice/3`, `Nx.stack/2`,
  `Nx.concatenate/2`, `Nx.gather/2`, …) come from Nx rather than being
  reimplemented here. `cast_input/2` also accepts a nested list
  (`[[1, 2], [3, 4]]`) or a flat list with an explicit `shape:` constraint.

  ## Storage

  Neo4j has no nested-list property, so a tensor stores as a flat value plus a
  `<attr>.shape` sidecar (row-major), chosen by `store`:

    * `:property` (default) — a native `LIST<INTEGER|FLOAT>` via `Nx.to_flat_list/1`;
      Cypher-visible.
    * `:packed` — a base64 `STRING` of `Nx.to_binary/1`; an opaque operand.

  The element type is **not** stored — it's the declared `type` constraint
  (schema, like an embedded-JSON attribute's target struct), recovered on read.
  Only shape is per-value data. This also eases migration: re-declaring the type
  needs no data rewrite.

  ## Constraints

    * `:type` — Nx element type, one of a closed set of shorthands (`:u8`,
      `:s64`, `:f32`, `:f8`, `:c64`, …). Defaults to `:u8`; the element type is
      **declared, never inferred** — input is cast to it, and read reconstructs
      from this constraint (inference couldn't work on read anyway).
    * `:shape` — optional fixed shape (e.g. `[3, 3]`); validated on cast.
    * `:store` — `:property` (default) or `:packed`.

  ## Usage

      attribute :weights, AshNeo4j.Type.NxTensor,
        constraints: [type: :f32, shape: [3, 3]]
  """

  use Ash.Type

  # The Nx element-type shorthands (Nx 0.12). Closed set — the `type` constraint
  # validates against it.
  @nx_types [
    :s2,
    :s4,
    :s8,
    :s16,
    :s32,
    :s64,
    :u2,
    :u4,
    :u8,
    :u16,
    :u32,
    :u64,
    :f8,
    :f16,
    :f32,
    :f64,
    :bf16,
    :c64,
    :c128
  ]

  @default_type :u8

  @doc false
  # Marker the data layer's TypeClassifier uses to route this through the
  # `:tensor` storage path.
  def ash_neo4j_tensor?, do: true

  @impl Ash.Type
  def storage_type(_constraints), do: :string

  @impl Ash.Type
  def constraints do
    [
      type: [
        type: {:one_of, @nx_types},
        default: @default_type,
        doc: "Nx element type — one of #{inspect(@nx_types)}. Defaults to `#{inspect(@default_type)}`; input is cast to it."
      ],
      shape: [
        type: {:list, :pos_integer},
        doc: "Optional fixed shape (e.g. `[3, 3]`). Validated on cast when set."
      ],
      store: [
        type: {:one_of, [:property, :packed]},
        default: :property,
        doc: "Storage codec: `:property` (native LIST, default) or `:packed` (base64 binary blob)."
      ]
    ]
  end

  @impl Ash.Type
  def cast_input(nil, _constraints), do: {:ok, nil}

  def cast_input(%Nx.Tensor{} = tensor, constraints) do
    apply_constraints(Nx.as_type(tensor, type(constraints)), constraints)
  end

  def cast_input(value, constraints) when is_list(value) do
    type = type(constraints)

    tensor =
      if constraints[:shape] && flat?(value) do
        value |> Nx.tensor(type: type) |> Nx.reshape(List.to_tuple(constraints[:shape]))
      else
        Nx.tensor(value, type: type)
      end

    apply_constraints(tensor, constraints)
  rescue
    e -> {:error, message: Exception.message(e)}
  end

  def cast_input(_, _), do: {:error, "expected a nested list, a flat list, or an %Nx.Tensor{}"}

  @impl Ash.Type
  def apply_constraints(%Nx.Tensor{} = tensor, constraints) do
    shape = tensor |> Nx.shape() |> Tuple.to_list()

    cond do
      length(shape) > 3 ->
        {:error, "tensors of rank > 3 are not supported yet (got rank #{length(shape)})"}

      constraints[:shape] && constraints[:shape] != shape ->
        {:error, "expected shape #{inspect(constraints[:shape])}, got #{inspect(shape)}"}

      true ->
        {:ok, tensor}
    end
  end

  def apply_constraints(value, _constraints), do: {:ok, value}

  @impl Ash.Type
  def cast_stored(nil, _constraints), do: {:ok, nil}

  def cast_stored(%Nx.Tensor{} = tensor, _constraints), do: {:ok, tensor}

  # The element type is schema (the declared `type` constraint), not stored — so
  # it's read from constraints here, exactly as an embedded-JSON attribute's
  # target struct is the schema's call. Only shape is per-value data.
  def cast_stored(%{data: data, shape: shape}, constraints) do
    nx_type = type(constraints)
    shape_tuple = List.to_tuple(shape)

    tensor =
      case constraints[:store] || :property do
        :packed -> data |> Base.decode64!() |> Nx.from_binary(nx_type) |> Nx.reshape(shape_tuple)
        :property -> data |> Nx.tensor(type: nx_type) |> Nx.reshape(shape_tuple)
      end

    {:ok, tensor}
  rescue
    e -> {:error, message: Exception.message(e)}
  end

  @impl Ash.Type
  def dump_to_native(nil, _constraints), do: {:ok, nil}
  # Fallback for Ash-level dumping; the data layer stores tensors via its own
  # dump_properties path (flat value + shape sidecar).
  def dump_to_native(%Nx.Tensor{} = tensor, _constraints), do: {:ok, Nx.to_flat_list(tensor)}
  def dump_to_native(_, _), do: :error

  @doc """
  Encodes a tensor for storage, returning `{stored_value, shape}` per the `store`
  codec — a flat `LIST` (`:property`) or a base64 `STRING` (`:packed`), plus the
  row-major shape. Used by the data layer's `dump_properties`. The element type
  is not stored — it's the declared `type` constraint, recovered on read.
  """
  @spec dump_storage(Nx.Tensor.t(), :property | :packed) :: {list() | binary(), [non_neg_integer()]}
  def dump_storage(%Nx.Tensor{} = tensor, store) do
    shape = tensor |> Nx.shape() |> Tuple.to_list()

    stored =
      case store do
        :packed -> tensor |> Nx.to_binary() |> Base.encode64()
        :property -> Nx.to_flat_list(tensor)
      end

    {stored, shape}
  end

  defp type(constraints), do: constraints[:type] || @default_type

  defp flat?(list), do: Enum.all?(list, &(not is_list(&1)))
end
