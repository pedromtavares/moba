defmodule MobaWeb.DuelView do
  use MobaWeb, :view

  alias MobaWeb.CommunityView

  def finished?(%{phase: "finished"}), do: true
  def finished?(_), do: false

  defdelegate formatted_body(body), to: CommunityView

  def phase_class(%{phase: phase}, current_phase) when phase == current_phase, do: "nav-link no-action active"
  def phase_class(_, _), do: "nav-link no-action"

  def pvp?(%{type: "pvp"}), do: true
  def pvp?(_), do: false

  def show_rematch?(%{duel: %{type: "pvp"} = duel, current_user: user}) do
    finished?(duel) && (user.id == duel.user_id || user.id == duel.opponent_id)
  end

  def show_rematch?(_), do: false

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
end
