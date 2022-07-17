defmodule Moba.Ranker do
  @moduledoc """
  Server responsible for updating global PVE and PVP rankings
  """
  use GenServer

  alias Moba.Game

  @limit 2000
  @tick 1000

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def init(_) do
    {:ok, %{timer: 0}}
  end

  def handle_cast(:pve, state) do
    Game.update_pve_ranking!()
    {:noreply, state}
  end

  @doc """
  Runs a timer before updating the PVP ranking to avoid deadlocks when running automated duels.
  Each cast resets the timer to 1 and schedules a check every tick, only updating after a time limit
  """
  def handle_cast(:pvp, state) do
    schedule_check()

    {:noreply, Map.put(state, :timer, 1)}
  end

  def handle_info(:check_timer, %{timer: timer} = state) do
    new_timer = check_timer(timer)

    {:noreply, Map.put(state, :timer, new_timer)}
  end

  defp check_timer(timer) when timer >= @limit do
    Game.update_pvp_ranking!()
    0
  end

  defp check_timer(timer) when timer > 0 do
    schedule_check()
    timer + @tick
  end

  defp check_timer(timer), do: timer

  defp schedule_check, do: Process.send_after(self(), :check_timer, @tick)
end
