defmodule Moba.Admin.Server do
  @moduledoc """
  Server responsible for keeping all relevant admin data
  """

  use GenServer

  alias Moba.Admin

  @timeout 1000 * String.to_integer(Application.get_env(:moba, :admin_refresh_seconds))

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def get_data do
    GenServer.call(__MODULE__, :data)
  end

  def init(_) do
    schedule_update()
    {:ok, current_state()}
  end

  def schedule_update, do: Process.send_after(self(), :server_update, @timeout)

  def handle_info(:server_update, _state) do
    state = current_state()
    MobaWeb.broadcast("admin", "server", %{})
    schedule_update()
    {:noreply, state}
  end

  @doc """
  Returns current match state or fetches from cache in the case of past matches
  """
  def handle_call(:data, _from, state) do
    {:reply, state, state}
  end

  defp current_state do
    %{
      players: Admin.current_active_players(),
      guests: Admin.current_guests()
    }
  end
end
