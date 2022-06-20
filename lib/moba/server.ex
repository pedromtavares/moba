defmodule Moba.Server do
  @moduledoc """
  Server responsible for managing the game's main timers
  """
  use GenServer

  # 30 secs
  @check_timeout 1000 * 30

  # 10mins
  @update_diff_in_seconds 60 * 10

  # 1 day
  @reset_diff_in_seconds 60 * 60 * 24

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

    match = Moba.current_match()

    if time_diff_in_seconds(match.inserted_at) >= @reset_diff_in_seconds do
      Moba.start!()
    end

    if time_diff_in_seconds(match.last_server_update_at) >= @update_diff_in_seconds do
      Moba.server_update!(match)
    end

    state
  end

  defp time_diff_in_seconds(nil), do: 0
  defp time_diff_in_seconds(field), do: Timex.diff(Timex.now(), field, :seconds)
end
