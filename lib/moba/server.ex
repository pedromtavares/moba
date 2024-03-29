defmodule Moba.Server do
  @moduledoc """
  Server responsible for managing the game's main timers
  """
  use GenServer

  alias Moba.{Cleaner, Conductor, Utils}

  # 30 secs
  @check_timeout 1000 * 30

  # 30mins
  @tick_diff_in_seconds 60 * 30

  # 24h
  @pvp_update_diff_in_seconds 24 * 60 * 60

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def init(state) do
    schedule_check()
    Process.send_after(self(), :warm_caches, 1000)
    {:ok, state}
  end

  def handle_info(:server_check, state) do
    with state = server_check(state) do
      {:noreply, state}
    end
  end

  def handle_info(:warm_caches, state) do
    unless test?() do
      Utils.run_async(fn ->
        Moba.cached_items()
        Moba.load_resource("tinker")
        Moba.pve_ranking()
        Moba.daily_ranking()
        Moba.season_ranking()
      end)
    end

    {:noreply, state}
  end

  defp schedule_check, do: Process.send_after(self(), :server_check, @check_timeout)

  defp server_check(state) do
    unless dev?() do
      schedule_check()
      season = Moba.current_season()

      if time_diff_in_seconds(season.last_server_update_at) >= @tick_diff_in_seconds do
        Conductor.season_tick!()
        Cleaner.cleanup_old_records()
      end

      if time_diff_in_seconds(season.last_pvp_update_at) >= @pvp_update_diff_in_seconds do
        Conductor.pvp_tick!()
      end
    end

    state
  end

  defp time_diff_in_seconds(nil), do: 0
  defp time_diff_in_seconds(field), do: Timex.diff(Timex.now(), field, :seconds)

  defp dev?, do: Application.get_env(:moba, :env) == :dev

  defp test?, do: Application.get_env(:moba, :env) == :test
end
