defmodule Moba.Ranker do
  @moduledoc """
  Server responsible for updating global PVE and PVP rankings
  """
  use GenServer

  alias Moba.Game

  @limit 5000
  @tick 1000

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def init(_) do
    {:ok, %{timer: 0}}
  end

  def handle_cast(:pve, state) do
    Game.rank_finished_heroes!()
    Cachex.put(:game_cache, "pve_ranking", Game.pve_ranking(Moba.pve_ranking_limit()))
    MobaWeb.broadcast("hero-ranking", "ranking", %{})
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
    Game.update_daily_ranking!()
    Game.update_season_ranking!()
    Cachex.put(:game_cache, "daily_ranking", Game.daily_ranking(Moba.daily_ranking_limit()))
    Cachex.put(:game_cache, "season_ranking", Game.season_ranking(Moba.season_ranking_limit()))
    Cachex.put(:game_cache, "pve_ranking_available", Game.available_top_heroes())
    MobaWeb.broadcast("player-ranking", "ranking", %{})
    0
  end

  defp check_timer(timer) when timer > 0 do
    schedule_check()
    timer + @tick
  end

  defp check_timer(timer), do: timer

  defp schedule_check, do: Process.send_after(self(), :check_timer, @tick)
end
