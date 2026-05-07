# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshNeo4j.Install.Docs do
  @moduledoc false

  def short_doc, do: "Installs AshNeo4j"
  def example, do: "mix igniter.install ash_neo4j"

  def long_doc do
    """
    #{short_doc()}

    ## Example

    ```bash
    #{example()}
    ```
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AshNeo4j.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"
    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :ash,
        installs: [{:ash, "~> 3.0"}],
        example: __MODULE__.Docs.example()
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      igniter
      |> Igniter.Project.Formatter.import_dep(:ash_neo4j)
      |> Spark.Igniter.prepend_to_section_order(:"Ash.Resource", [:neo4j])
      |> Igniter.Project.Config.configure(
        "runtime.exs",
        :bolty,
        [Bolt, :uri],
        "bolt://localhost:7687"
      )
      |> Igniter.Project.Config.configure(
        "runtime.exs",
        :bolty,
        [Bolt, :auth],
        [username: "neo4j", password: "password"]
      )
      |> Igniter.Project.Config.configure(
        "runtime.exs",
        :bolty,
        [Bolt, :pool_size],
        10
      )
      |> Igniter.Project.Config.configure(
        "runtime.exs",
        :bolty,
        [Bolt, :name],
        Bolt
      )
      |> Igniter.Project.Application.add_new_child(
        {Bolty, {:code, quote(do: Application.get_env(:bolty, Bolt))}}
      )
    end
  end
else
  defmodule Mix.Tasks.AshNeo4j.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"
    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The task 'ash_neo4j.install' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
