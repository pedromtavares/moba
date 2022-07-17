defmodule Moba.Server do
  @moduledoc """
  Server responsible for managing the game's main timers
  """
  use GenServer

  # 30 secs
  @check_timeout 1000 * 30

  # 10mins
  @tick_diff_in_seconds 60 * 10

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def init(state) do
    schedule_check()
    {:ok, state}
  end

  def handle_info(:server_check, state) do
    with state = server_check(state) do
      {:noreply, state}
    end
  end

  defp schedule_check, do: Process.send_after(self(), :server_check, @check_timeout)

  defp server_check(state) do
    schedule_check()

    season = Moba.current_season()

    if time_diff_in_seconds(season.last_server_update_at) >= @tick_diff_in_seconds do
      Moba.server_tick!(season)
    end

    state
  end

  defp time_diff_in_seconds(nil), do: 0
  defp time_diff_in_seconds(field), do: Timex.diff(Timex.now(), field, :seconds)
end
