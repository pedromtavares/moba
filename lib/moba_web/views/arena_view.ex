defmodule MobaWeb.ArenaView do
  use MobaWeb, :view
  alias MobaWeb.PlayerView

  def auto_matches_percentage(auto_matches) do
    length(auto_matches) * 100 / Moba.daily_match_limit()
  end

  def can_be_challenged?(%{last_challenge_at: nil}, _), do: true

  def can_be_challenged?(%{last_challenge_at: time}, current_time) do
    Timex.diff(Timex.shift(time, seconds: 30), current_time) < 0
  end

  def elite?(%{type: "elite_matchmaking"}), do: true
  def elite?(_), do: false

  def first_battle_for(%{id: duel_id, player_first_pick_id: hero_id}, battles),
    do: duel_battle(duel_id, hero_id, battles)

  def last_battle_for(%{id: duel_id, opponent_second_pick_id: hero_id}, battles),
    do: duel_battle(duel_id, hero_id, battles)

  def finished?(%{phase: "finished"}), do: true
  def finished?(_), do: false

  def duel_badge_class(%{type: type}) do
    case type do
      "pvp" -> "badge badge-light-danger"
      "elite_matchmaking" -> "badge badge-light-warning"
      _ -> "badge badge-light-primary"
    end
  end

  def duel_label(%{type: "elite_matchmaking"}), do: "Elite MM"
  def duel_label(%{type: "pvp"}), do: "Duel"
  def duel_label(_), do: "Normal MM"

  def duel_result(duel, player_id \\ nil) do
    player_id = player_id || duel.player_id

    cond do
      duel.phase != "finished" -> content_tag(:h5, "In Progress")
      is_nil(duel.winner_player) -> content_tag(:h5, "Tie", class: "text-white")
      duel.winner_player_id == player_id -> content_tag(:h5, "Victory", class: "text-success")
      true -> content_tag(:h5, "Defeat", class: "text-muted")
    end
  end

  def manual_matches_percentage(manual_matches) do
    length(manual_matches) * 100 / Moba.daily_match_limit()
  end

  def match_result(match) do
    cond do
      match.phase != "scored" -> content_tag(:h5, "In Progress")
      match.winner_id == match.player_id -> content_tag(:h5, "Victory", class: "text-success")
      true -> content_tag(:h5, "Defeat", class: "text-muted")
    end
  end

  def match_type(%{type: "auto"}), do: content_tag(:span, "A", data: [toggle: "tooltip"], title: "Auto Match")
  def match_type(%{type: "manual"}), do: content_tag(:span, "M", data: [toggle: "tooltip"], title: "Manual Match")

  def next_pvp_tier_percentage(%{pvp_tier: current_tier, pvp_points: pvp_points}) do
    current = Game.pvp_points_for(current_tier)
    max = Game.pvp_points_for(current_tier + 1)
    (pvp_points - current) * 100 / (max - current)
  end

  def next_pvp_tier(%{pvp_tier: current_tier}) do
    cond do
      current_tier >= Moba.max_pvp_tier() -> nil
      true -> current_tier + 1
    end
  end

  def opponent_for(duel, %{id: id}) when duel.player_id == id, do: duel.opponent_player
  def opponent_for(duel, _), do: duel.player

  def reset_timer do
    last_pvp_time = Moba.current_season().last_pvp_update_at

    time =
      last_pvp_time
      |> Timex.shift(days: 1)
      |> Timex.format("{relative}", :relative)
      |> elem(1)

    "A new fight begins #{time}"
  end

  def rewards_badge(rewards) when rewards == 0, do: ""

  def rewards_badge(rewards) when rewards > 0 do
    content_tag("span", "+#{rewards} Season Points", class: "badge badge-pill badge-light-success")
  end

  def rewards_badge(rewards) do
    content_tag("span", "#{rewards} Season Points", class: "badge badge-pill badge-light-dark")
  end

  def silenced?(%{current_player: %{status: "silenced"}}), do: true
  def silenced?(_), do: false

  def tier_buff(%{player: %{current_immortal_streak: streak}} = assigns) when streak > 0 do
    nerf = Float.round(streak * Moba.immortal_streak_multiplier() * 100, 1)
    assigns = Map.put(assigns, :nerf, nerf)

    ~H"""
      <span class='badge badge-light-danger mt-2' data-toggle="tooltip" title="The title of being The Immortal comes with a weakness."><i class='fa-solid fa-diamond mr-1'></i>- <%= @nerf %>% Hero Stats</span>
    """
  end

  def tier_buff(assigns),
    do: ~H"""
      <span></span>
    """

  def tier_label(%{pvp_tier: 2}), do: "Immortal"
  def tier_label(%{pvp_tier: 1}), do: "Shadow"
  def tier_label(_), do: "Pleb"

  def tier_title(%{pvp_tier: 2, ranking: 1}), do: "You are The Immortal, defend your title."
  def tier_title(%{pvp_tier: 2}), do: "You are an Immortal, fighting among the best for the title."
  def tier_title(%{pvp_tier: 1}), do: "You are a Shadow, rise above the rest to become an Immortal."
  def tier_title(_), do: "You are a Pleb, fight to become a Shadow."

  def pvp?(%{type: "pvp"}), do: true
  def pvp?(_), do: false

  defp duel_battle(duel_id, hero_id, battles) do
    Enum.find(battles, &(&1.attacker_id == hero_id && &1.duel_id == duel_id))
  end
end
