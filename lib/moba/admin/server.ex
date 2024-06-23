defmodule Moba.Admin.Server do
  @moduledoc """
  Server responsible for keeping all relevant admin data
  """

  use GenServer

  alias Moba.{Admin, Utils}

  @timeout 1000 * String.to_integer(Application.compile_env(:moba, :admin_refresh_seconds))

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def get_data do
    GenServer.call(__MODULE__, :data)
  end

  def init(_) do
    update_cache()
    schedule_update()
    {:ok, %{}}
  end

  def handle_info(:server_update, state) do
    update_cache()
    schedule_update()
    {:noreply, state}
  end

  @doc """
  Returns current match state or fetches from cache
  """
  def handle_call(:data, _from, state) do
    new_state =
      case Cachex.get(:game_cache, "match_stats") do
        {:ok, nil} -> state
        {:ok, stats} -> stats
      end

    {:reply, new_state, new_state}
  end

  defp current_state do
    %{
      players: Admin.current_active_players(),
      guests: Admin.current_guests(),
      user_stats: Admin.get_user_stats(),
      duels: Admin.list_recent_duels(),
      match_stats: Admin.match_stats(),
      masters_count: Admin.masters_count(),
      grandmasters_count: Admin.grandmasters_count(),
      undefeated_count: Admin.undefeated_count(),
      active_players_count: Admin.active_players_count(),
      trained_heroes_count: Admin.trained_heroes_count()
    }
  end

  defp schedule_update, do: Process.send_after(self(), :server_update, @timeout)

  defp update_cache do
    Utils.run_async(fn ->
      state = current_state()
      Cachex.put(:game_cache, "match_stats", state)
      MobaWeb.broadcast("admin", "server", %{})
    end)
  end
end
