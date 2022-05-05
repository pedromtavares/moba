defmodule MobaWeb.DuelView do
  use MobaWeb, :view

  alias MobaWeb.Presence

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

  def show_rematch?(%{duel: %{type: "pvp"} = duel, current_user: user}) do
    finished?(duel) && both_online?(duel, user) && (user.id == duel.user_id || user.id == duel.opponent_id)
  end

  def show_rematch?(_), do: false

  def show_timer?(%{type: "pvp", phase: phase}) when phase not in ["user_battle", "opponent_battle", "finished"],
    do: true

  def show_timer?(_), do: false

  def title(%{type: "normal_matchmaking"}), do: "Normal Matchmaking"
  def title(%{type: "elite_matchmaking"}), do: "Elite Matchmaking"
  def title(_), do: ""

  def user_instructions(%{phase: phase, user: user}) when phase in ["user_first_pick", "user_second_pick"] do
    "#{user.username}, it's your turn to pick"
  end

  def user_instructions(_), do: ""

  def opponent_instructions(%{phase: phase, opponent: opponent})
      when phase in ["opponent_first_pick", "opponent_second_pick"] do
    "#{opponent.username}, it's your turn to pick"
  end

  def opponent_instructions(_), do: ""

  defp both_online?(%{user_id: user_id, opponent_id: opponent_id}, current_user) do
    online_ids =
      Presence.list("online")
      |> Enum.map(fn {_user_id, data} -> List.first(data[:metas]) end)
      |> Enum.map(& &1.user_id)
      |> Kernel.++([current_user.id])

    Enum.member?(online_ids, user_id) && Enum.member?(online_ids, opponent_id)
  end
end
