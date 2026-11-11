defmodule MobaWeb.V2.Hooks.BattlePreferences do
  @moduledoc "Loads and saves battle presentation settings for the viewing player."
  import Phoenix.Component
  import Phoenix.LiveView

  alias Moba.Game

  def on_mount(:default, _params, _session, socket) do
    speed = Map.get(socket.assigns.current_player.preferences || %{}, :battle_speed, :normal)

    {:cont,
     socket
     |> assign(:battle_speed, speed)
     |> attach_hook(:battle_preferences, :handle_event, &handle_event/3)}
  end

  defp handle_event("battle-speed", %{"speed" => speed}, socket) when speed in ~w(normal fast instant) do
    player = Game.update_preferences!(socket.assigns.current_player, %{battle_speed: speed})
    {:halt, assign(socket, current_player: player, battle_speed: player.preferences.battle_speed)}
  end

  defp handle_event("battle-speed", _params, socket), do: {:halt, socket}
  defp handle_event(_event, _params, socket), do: {:cont, socket}
end
