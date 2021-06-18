defmodule Moba.Admin.Server do
  @moduledoc """
  Server responsible for keeping all relevant admin data
  """

  use GenServer

  alias Moba.{Admin, Game}

  @timeout 1000 * String.to_integer(Application.get_env(:moba, :admin_refresh_seconds))

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
    state = current_state()
    MobaWeb.broadcast("admin", "server", %{})
    {:noreply, state}
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
      players = Admin.current_active_players()
      arena = Admin.current_arena_heroes()
      rates = Admin.recent_winrates(match.inserted_at)

      %{
        players: players,
        arena: arena,
        rates: rates
      }
    else
      %{
        players: [],
        arena: [],
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

    arena =
      Enum.map(match.winners, fn {ranking, winner_id} ->
        Map.put(Game.get_hero!(winner_id), :pvp_ranking, String.to_integer(ranking))
      end)

    data = %{
      rates: rates,
      players: [],
      arena: arena
    }

    Cachex.put(:game_cache, key, data)
    data
  end
end
