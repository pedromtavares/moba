defmodule Moba.Ranker do
  @moduledoc """
  Server responsible for updating global PVE and PVP rankings
  """
  use GenServer

  alias Moba.Game

  @limit 5000

  def start_link(opts), do: GenServer.start_link(__MODULE__, [], Keyword.put_new(opts, :name, __MODULE__))

  def init(_) do
    {:ok, %{timer_ref: nil, token: nil}}
  end

  def handle_cast(:pve, state) do
    Game.rank_finished_heroes!()
    Cachex.put(:game_cache, "pve_ranking", Game.pve_ranking(Moba.pve_ranking_limit()))
    MobaWeb.broadcast("hero-ranking", "ranking", %{})
    {:noreply, state}
  end

  def handle_cast(:pvp, state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    token = make_ref()
    ref = Process.send_after(self(), {:update_pvp, token}, @limit)
    {:noreply, %{state | timer_ref: ref, token: token}}
  end

  def handle_info({:update_pvp, token}, %{token: token} = state) do
    Game.update_daily_ranking!()
    Game.update_season_ranking!()
    Cachex.put(:game_cache, "daily_ranking", Game.daily_ranking(Moba.daily_ranking_limit()))
    Cachex.put(:game_cache, "season_ranking", Game.season_ranking(Moba.season_ranking_limit()))
    Cachex.put(:game_cache, "pve_ranking_available", Game.available_top_heroes())
    MobaWeb.broadcast("player-ranking", "ranking", %{})
    {:noreply, %{state | timer_ref: nil, token: nil}}
  end

  def handle_info({:update_pvp, _token}, state), do: {:noreply, state}
end
