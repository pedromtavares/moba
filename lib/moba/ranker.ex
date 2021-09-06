defmodule Moba.Ranker do
  @moduledoc """
  Server responsible for Arena ranking updates
  """
  use GenServer

  alias Moba.Game

  # 5 secs
  @check_timeout 1000 * 5

  def master do
    GenServer.cast(__MODULE__, {:increment, :master})
  end

  def grandmaster do
    GenServer.cast(__MODULE__, {:increment, :grandmaster})
  end

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def init(_) do
    schedule_check()
    {:ok, %{master: 0, grandmaster: 0}}
  end

  def schedule_check, do: Process.send_after(self(), :server_check, @check_timeout)

  def handle_info(:server_check, state) do
    state = if state.master > 0, do: update_and_broadcast(state, 5), else: state

    state = if state.grandmaster > 0, do: update_and_broadcast(state, 6), else: state

    schedule_check()
    {:noreply, state}
  end

  def handle_cast({:increment, key}, state) do
    {:noreply, Map.put(state, key, state[key] + 1)}
  end

  defp update_and_broadcast(state, tier) do
    key = if tier == Moba.master_league_tier(), do: :master, else: :grandmaster
    heroes = Game.update_pvp_ranking!(tier)

    Enum.each(heroes, &Game.broadcast_to_hero(&1.id))

    Map.put(state, key, 0)
  end
end
