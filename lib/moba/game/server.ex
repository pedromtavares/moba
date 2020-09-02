defmodule Moba.Game.Server do
  @moduledoc """
  Gameplay server responsible for timed operations like restarting the match
  """

  use GenServer

  alias Moba.Game

  # 10 secs
  @timeout 1000 * 30

  # 10mins
  @update_diff_in_seconds 60 * 10

  # 1 day
  @reset_diff_in_seconds 60 * 60 * 24

  # 12 hours
  @new_round_diff_in_seconds 60 * 60 * Moba.pvp_round_timeout_in_hours()

  def start_link(_), do: GenServer.start_link(__MODULE__, [])

  def init(state) do
    schedule_update()
    {:ok, state}
  end

  def schedule_update, do: Process.send_after(self(), :server_update, @timeout)

  def handle_info(:server_update, state) do
    schedule_update()

    check_restart()

    check_update()

    check_pvp_round()

    {:noreply, state}
  end

  defp check_restart do
    match = Game.current_match()
    diff = diff_for(match.inserted_at)

    if diff >= @reset_diff_in_seconds, do: Moba.start!()
  end

  defp check_update do
    match = Game.current_match()
    diff = diff_for(match.last_server_update_at)

    if diff >= @update_diff_in_seconds, do: Game.server_update!(match)
  end

  defp check_pvp_round do
    match = Game.current_match()
    diff = diff_for(match.last_pvp_round_at)

    if diff >= @new_round_diff_in_seconds, do: Game.new_pvp_round!(match)
  end

  defp diff_for(nil), do: 0
  defp diff_for(field), do: Timex.diff(Timex.now(), field, :seconds)
end
