defmodule Moba.Admin.Server do
  @moduledoc """
  Server responsible for keeping all relevant admin data
  """

  use GenServer

  alias Moba.{Admin, Game}

  # 300 secs
  @timeout 1000 * 300

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def get_data(match) do
    GenServer.call(__MODULE__, {:data, match})
  end

  def init(_) do
    schedule_update()
    {:ok, current_state()}
  end

  def schedule_update, do: Process.send_after(self(), :server_update, @timeout)

  def handle_info(:server_update, _state) do
    schedule_update()
    {:noreply, current_state()}
  end

  @doc """
  Returns current match state or fetches from cache in the case of past matches
  """
  def handle_call({:data, match}, _from, state) do
    data =
      if match == Game.current_match() do
        state
      else
        get_cached_data(match)
      end

    {:reply, data, state}
  end

  defp current_state do
    match = Game.current_match()

    if match do
      {players, bots} = Admin.current_arena_heroes()

      rates = Admin.recent_winrates(match.inserted_at)

      %{
        players: players,
        bots: bots,
        rates: rates
      }
    else
      %{
        players: [],
        bots: [],
        rates: []
      }
    end
  end

  defp get_cached_data(match) do
    key = "admin-match-#{match.id}"

    case Cachex.get(:game_cache, key) do
      {:ok, nil} -> put_cache_data(match)
      {:ok, data} -> data
    end
  end

  defp put_cache_data(match) do
    key = "admin-match-#{match.id}"
    rates = Admin.recent_winrates(match.inserted_at)

    players =
      Enum.map(match.winners, fn {ranking, winner_id} ->
        Map.put(Game.get_hero!(winner_id), :pvp_ranking, String.to_integer(ranking))
      end)

    data = %{
      rates: rates,
      players: players,
      bots: []
    }

    Cachex.put(:game_cache, key, data)
    data
  end
end
