defmodule AshNeo4j.DataLayer.BoltxHelper do

  @moduledoc """
  AshNeo4j DataLayer BoltxHelper functions
  """

  @doc """
  Converts a Boltx.Types.Duration to an Elixir Duration

  ## Examples
  ```
  iex> AshNeo4j.DataLayer.BoltxHelper.to_elixir_duration(Boltx.Types.Duration.create(14, 25, 18367, 8000))
  %Duration{year: 1, month: 2, week: 3, day: 4, hour: 5, minute: 6, second: 7, microsecond: {8, 6}}

  iex> AshNeo4j.DataLayer.BoltxHelper.to_elixir_duration(Boltx.Types.Duration.create(1, 0, 0, 0))
  %Duration{month: 1}
  ```
  """
  def to_elixir_duration(value) when is_struct(value, Boltx.Types.Duration) do
    if value.nanoseconds == 0 do
      %{}
    else
      # microsecond from nanoseconds, losing precision
      %{microsecond: {Integer.floor_div(value.nanoseconds, 1000), 6}}
    end
    |> Map.put(:year, value.years)
    |> Map.put(:month, value.months)
    |> Map.put(:week, Integer.floor_div(value.days, 7)) # excess days
    |> Map.put(:day, Integer.mod(value.days, 7)) # remainder days
    |> Map.put(:hour, value.hours)
    |> Map.put(:minute, value.minutes)
    |> Map.put(:second, value.seconds)
    |> Duration.new!()
    #|> IO.inspect(label: :to_elixir_duration_result)
  end

  @doc """
  Converts an Elixir Duration to a Boltx.Types.Duration

  ## Examples
  ```
  iex> AshNeo4j.DataLayer.BoltxHelper.from_elixir_duration(Duration.new!(%{year: 1, month: 2, week: 3, day: 4, hour: 5, minute: 6, second: 7, microsecond: {8, 6}}))
  %Boltx.Types.Duration{years: 1, months: 2, weeks: 0, days: 25, hours: 5, minutes: 6, seconds: 7, nanoseconds: 8000}

  iex> AshNeo4j.DataLayer.BoltxHelper.from_elixir_duration(Duration.new!(%{month: 1}))
  %Boltx.Types.Duration{years: 0, months: 1, weeks: 0, days: 0, hours: 0, minutes: 0, seconds: 0, nanoseconds: 0}
  ```
  """
  def from_elixir_duration(value) when is_struct(value, Duration) do
    months = value.year * 12 + value.month
    days = value.week * 7 + value.day
    seconds = value.hour * 3600 + value.minute * 60 + value.second
    nanoseconds =
      cond do
        value.microsecond == nil ->
          0
        true ->
          { ms, _precision} = value.microsecond
          ms * 1000
      end
    Boltx.Types.Duration.create(months, days, seconds, nanoseconds)
    #|> IO.inspect(label: :from_elixir_duration_result)
  end
end
