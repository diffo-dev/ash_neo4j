defmodule AshNeo4j.DataLayer.Transformer do
  @moduledoc false
  use Spark.Dsl.Transformer

  def transform(dsl) do
    properties = AshNeo4j.DataLayer.Info.store(dsl)

    func_args =
      Enum.map(properties, fn name ->
        {name, [], Elixir}
      end)

    fields =
      Enum.map(properties, fn property ->
        attribute = Ash.Resource.Info.attribute(dsl, property)
        matcher = {property, [], Elixir}

        value =
          if Ash.Type.ecto_type(attribute.type) in [:string, :uuid, :binary_id] do
            quote do
              unquote(matcher)
            end
          else
            quote do
              if unquote(matcher) == "" do
                nil
              else
                unquote(matcher)
              end
            end
          end

        quote do
          value = unquote(value)

          unquote(matcher) =
            case Ash.Type.cast_stored(
                   unquote(Macro.escape(attribute.type)),
                   value,
                   unquote(Macro.escape(attribute.constraints))
                 ) do
              {:ok, value} ->
                value

              :error ->
                throw(
                  {:error,
                   "stored value for #{unquote(property)} could not be casted from the stored value to type #{unquote(inspect(Macro.escape(attribute.type)))}: #{inspect(value)}"}
                )
            end
        end
      end)

    dump_fields =
      Enum.map(properties, fn property ->
        attribute = Ash.Resource.Info.attribute(dsl, property)
        matcher = {property, [], Elixir}

        quote do
          value = unquote(matcher)

          unquote(matcher) =
            case Ash.Type.dump_to_embedded(
                   unquote(Macro.escape(attribute.type)),
                   value,
                   unquote(Macro.escape(attribute.constraints))
                 ) do
              {:ok, value} ->
                value

              :error ->
                throw(
                  {:error,
                   "stored value for #{unquote(property)} could not be dumped to type #{inspect(unquote(Macro.escape(attribute.type)))}: #{inspect(value)}"}
                )
            end
        end
      end)

    map = {:%{}, [], Enum.map(properties, fn property -> {property, {property, [], Elixir}} end)}

    struct =
      {:struct, [],
       [
         Spark.Dsl.Transformer.get_persisted(dsl, :module),
         map
       ]}

    {:ok,
      Spark.Dsl.Transformer.eval(
        dsl,
        [],
        quote do
          def ash_neo4j_dump_node(unquote(map)) do
            {:ok, unquote(dump_fields)}
          catch
            {:error, error} ->
              {:error, error}
          end

          def ash_neo4j_parse_node([unquote_splicing(func_args) | _]) do
            unquote(fields)
            {:ok, unquote(struct)}
          catch
            {:error, error} ->
              {:error, error}
          end

          def ash_neo4j_parse_node([unquote_splicing(func_args)]) do
            {:error, "Invalid node #{inspect([unquote_splicing(func_args)])}"}
          end
        end
      )}
  end
end
