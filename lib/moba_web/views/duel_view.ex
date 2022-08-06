defmodule MobaWeb.DuelView do
  use MobaWeb, :view

  alias MobaWeb.Presence

  def casual?(%{player: %{pvp_points: player_sp}, opponent_player: %{pvp_points: opponent_sp}})
      when player_sp - opponent_sp < -200 or player_sp - opponent_sp > 200 do
    true
  end

  def casual?(_), do: false

  def finished?(%{phase: "finished"}), do: true
  def finished?(_), do: false

  def pick_timer(%{phase_changed_at: changed}, current_time) do
    seconds_per_pick = Moba.duel_timer_in_seconds()
    target = Timex.shift(changed, seconds: seconds_per_pick)
    Timex.diff(target, current_time, :seconds)
  end

  def phase_class(%{phase: phase}, current_phase) when phase == current_phase, do: "nav-link no-action active"
  def phase_class(_, _), do: "nav-link no-action"

  def pvp?(%{type: "pvp"}), do: true
  def pvp?(_), do: false

  def show_rematch?(%{duel: %{type: "pvp"} = duel, current_player: player}) do
    finished?(duel) && both_online?(duel, player) &&
      (player.id == duel.player_id || player.id == duel.opponent_player_id)
  end

  def show_rematch?(_), do: false

  def show_timer?(%{type: "pvp", phase: phase}) when phase not in ["player_battle", "opponent_battle", "finished"],
    do: true

  def show_timer?(_), do: false

  def title(%{type: "normal_matchmaking"}), do: "Normal Matchmaking"
  def title(%{type: "elite_matchmaking"}), do: "Elite Matchmaking"
  def title(_), do: ""

  def user_instructions(%{phase: phase, player: player}) when phase in ["player_first_pick", "player_second_pick"] do
    "#{player.user.username}, it's your turn to pick"
  end

  def user_instructions(_), do: ""

  def opponent_instructions(%{phase: phase, opponent_player: opponent})
      when phase in ["opponent_first_pick", "opponent_second_pick"] do
    "#{opponent.user.username}, it's your turn to pick"
  end

  def opponent_instructions(_), do: ""

  defdelegate username(player), to: MobaWeb.UserView

  defp both_online?(%{player: %{id: player_id}, opponent_player: %{id: opponent_id}}, current_player) do
    online_ids =
      Presence.list("online")
      |> Enum.map(fn {_user_id, data} -> List.first(data[:metas]) end)
      |> Enum.map(& &1.player_id)
      |> Kernel.++([current_player.id])

    Enum.member?(online_ids, player_id) && Enum.member?(online_ids, opponent_id)
  end
end
