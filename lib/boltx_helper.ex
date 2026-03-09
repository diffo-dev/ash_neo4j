# SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.BoltxHelper do
  @moduledoc """
  AshNeo4j BoltxHelper
  """

  @dialyzer {:nowarn_function, start: 1}
  @doc """
  Starts Boltx, returns :ok or {:error, error}
  """
  def start() do
    start(Application.get_env(:boltx, Bolt))
  end

  @doc """
  Starts Boltx with config, returns :ok or {:error, error}
  """
  def start(config) do
    case Boltx.start_link(config) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Checks Boltx connectivity
  """
  def is_connected() do
    try do
      Boltx.query!(Bolt, "return 1 as n") |> Boltx.Response.first() == %{"n" => 1}
    catch
      :exit, _ -> false
    end
  end

  @doc """
  Converts an Elixir DateTime to a Boltx.Types.DateTimeWithTZOffset

  ### Examples

      iex> AshNeo4j.BoltxHelper.convert_to_datetime_with_tz_offset(~U[2025-12-31T23:59:59Z])
      %Boltx.Types.DateTimeWithTZOffset{naive_datetime: ~N[2025-12-31 23:59:59], timezone_offset: 0}

  """
  def convert_to_datetime_with_tz_offset(datetime) when is_struct(datetime, DateTime) do
    %DateTime{
      year: year,
      month: month,
      day: day,
      hour: hour,
      minute: minute,
      second: second,
      microsecond: microsecond,
      utc_offset: utc_offset
    } = datetime

    naive_datetime = NaiveDateTime.new!(year, month, day, hour, minute, second, microsecond, Calendar.ISO)
    Boltx.Types.DateTimeWithTZOffset.create(naive_datetime, utc_offset || 0)
  end

  @doc """
  Converts an Elixir DateTime from a Boltx.Types.DateTimeWithTZOffset, shifting by the timezone offset

  ### Examples

      iex> AshNeo4j.BoltxHelper.convert_from_datetime_with_tz_offset(%Boltx.Types.DateTimeWithTZOffset{naive_datetime: ~N[2025-12-31 23:59:59], timezone_offset: 0})
      ~U[2025-12-31T23:59:59Z]

      iex> AshNeo4j.BoltxHelper.convert_from_datetime_with_tz_offset(%Boltx.Types.DateTimeWithTZOffset{naive_datetime: ~N[2025-12-31 23:59:59], timezone_offset: 37_800})
      ~U[2026-01-01T10:29:59Z]

  """
  def convert_from_datetime_with_tz_offset(datetime_with_tz_offset)
      when is_struct(datetime_with_tz_offset, Boltx.Types.DateTimeWithTZOffset) do
    datetime = DateTime.from_naive!(datetime_with_tz_offset.naive_datetime, "Etc/UTC")
    DateTime.shift(datetime, second: datetime_with_tz_offset.timezone_offset)
  end

  @doc """
  Converts an Elixir Time to a Boltx.Types.TimeWithTZOffset, with a zero timezone offset

  ### Examples

      iex> AshNeo4j.BoltxHelper.convert_to_time_with_tz_offset(~T[23:59:59Z])
      %Boltx.Types.TimeWithTZOffset{time: ~T[23:59:59], timezone_offset: 0}

  """
  def convert_to_time_with_tz_offset(time) when is_struct(time, Time) do
    %Boltx.Types.TimeWithTZOffset{time: time, timezone_offset: 0}
  end

  @doc """
  Converts an Elixir Time from a Boltx.Types.TimeWithTZOffset, ignoring the timezone offset

  ### Examples

      iex> AshNeo4j.BoltxHelper.convert_from_time_with_tz_offset(%Boltx.Types.TimeWithTZOffset{time: ~T[23:59:59], timezone_offset: 0})
      ~T[23:59:59]

  """
  def convert_from_time_with_tz_offset(time) when is_struct(time, Boltx.Types.TimeWithTZOffset) do
    time.time
  end
end
