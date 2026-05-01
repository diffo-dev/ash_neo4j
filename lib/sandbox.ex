# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.Sandbox do
  @moduledoc """
  Test sandbox for AshNeo4j, analogous to `Ecto.Adapters.SQL.Sandbox`.

  Each test that calls `checkout/0` gets a dedicated Neo4j connection with an
  open transaction. Every Cypher query executed by that test process runs
  inside that transaction. When the test process exits the transaction is
  rolled back automatically, so no data persists between tests and safe
  parallel execution (`async: true`) is possible.

  ## Usage

  Replace the `Neo4jHelper.delete_all()` pattern with a sandbox checkout:

      setup do
        AshNeo4j.Sandbox.checkout()
        on_exit(&AshNeo4j.Sandbox.rollback/0)
      end

  The `on_exit` call is optional. ExUnit's on_exit callbacks run in a separate
  process after the test process has already exited, so by the time
  `rollback/0` is called the transaction has already been rolled back via the
  holder's exit-signal trap. Including `on_exit(&AshNeo4j.Sandbox.rollback/0)`
  is harmless (it becomes a no-op) and is recommended for clarity.

  ## How it works

  `checkout/0` spawns a *holder* process linked to the test process. The holder
  opens a `Bolty.transaction/3` and waits for query messages. All
  `Cypher.run/2` calls from the test process are forwarded to the holder and
  executed on the single sandboxed connection, keeping every write inside the
  uncommitted transaction.

  When the test process exits (pass, fail, or crash) the link delivers an exit
  signal to the holder. Because the holder traps exits, the signal becomes a
  message that triggers `Bolty.rollback/2`, cleanly rolling back the
  transaction and returning the connection to the pool.

  ## Parallel tests

  Because each test's writes are confined to an isolated transaction that is
  never committed, concurrent tests cannot interfere with each other:

      use ExUnit.Case, async: true

      setup do
        AshNeo4j.Sandbox.checkout()
        on_exit(&AshNeo4j.Sandbox.rollback/0)
      end
  """

  @pdict_key :ash_neo4j_sandbox

  @doc """
  Checks out a sandbox connection and begins a Neo4j transaction.

  All Cypher queries from the calling process are routed to this connection and
  executed within the open transaction. The transaction is rolled back
  automatically when the calling process exits.

  Raises if called more than once without an intervening `rollback/0`.
  """
  @spec checkout() :: :ok
  def checkout do
    if Process.get(@pdict_key) do
      raise "AshNeo4j.Sandbox already checked out for this process — call rollback/0 first"
    end

    parent = self()

    holder =
      spawn_link(fn ->
        # Trap exits so the parent's death arrives as a message rather than
        # killing the holder before Bolty.rollback/2 can be called.
        Process.flag(:trap_exit, true)

        Bolty.transaction(Bolt, fn conn ->
          send(parent, {:ash_neo4j_sandbox_ready, self()})
          holder_loop(conn)
        end)
      end)

    receive do
      {:ash_neo4j_sandbox_ready, ^holder} ->
        Process.put(@pdict_key, holder)
        :ok
    after
      5_000 ->
        Process.exit(holder, :kill)
        raise "AshNeo4j.Sandbox.checkout/0 timed out waiting for the transaction to open"
    end
  end

  @doc """
  Rolls back the sandbox transaction for the current process.

  When called from the same process as `checkout/0` this signals the holder to
  roll back immediately and blocks until the rollback completes.

  When called from an `on_exit` callback (which runs in a different process
  after the test process has already exited) this is a safe no-op — the
  transaction has already been rolled back via the holder's exit-signal trap.
  """
  @spec rollback() :: :ok
  def rollback do
    case Process.delete(@pdict_key) do
      nil ->
        :ok

      holder ->
        ref = Process.monitor(holder)
        send(holder, :rollback)

        receive do
          {:DOWN, ^ref, :process, ^holder, _} -> :ok
        after
          5_000 -> :ok
        end
    end
  end

  @doc false
  @spec active?() :: boolean()
  def active?, do: Process.get(@pdict_key) != nil

  @doc false
  @spec run(String.t(), map()) :: {:ok, Bolty.Response.t()} | {:error, any()} | nil
  def run(cypher, params) do
    case Process.get(@pdict_key) do
      nil ->
        nil

      holder ->
        ref = make_ref()
        send(holder, {:query, self(), ref, cypher, params})

        receive do
          {^ref, result} -> result
        after
          30_000 -> {:error, "AshNeo4j.Sandbox query timed out after 30s"}
        end
    end
  end

  defp holder_loop(conn) do
    receive do
      {:query, caller, ref, cypher, params} ->
        result = Bolty.query(conn, cypher, params)
        send(caller, {ref, result})
        holder_loop(conn)

      :rollback ->
        Bolty.rollback(conn, :sandbox_rollback)

      {:EXIT, _pid, _reason} ->
        Bolty.rollback(conn, :sandbox_rollback)
    end
  end
end
