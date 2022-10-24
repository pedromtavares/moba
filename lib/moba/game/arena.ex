defmodule Moba.Game.Arena do
  @moduledoc """
  Module focused on cross-resource orchestration and logic related to PvP (Duels & Matchmaking)
  """
  alias Moba.{Engine, Game}
  alias Game.{Duels, Heroes, Matches, Players}

  @daily_match_limit 30

  def auto_matchmaking!(player), do: create_match!(player, Players.matchmaking_opponent(player), "auto")

  def auto_next_duel_phase!(duel) do
    updated = Duels.auto_next_phase!(duel)
    MobaWeb.broadcast("duel-#{duel.id}", "phase", updated.phase)
    updated
  end

  def clear_auto_matches!(player) do
    if Matches.can_clear_auto_matches?(player) do
      Matches.clear_auto!(player)
      total_wins = player.total_wins - player.daily_wins
      total_matches = player.total_matches - player.daily_matches

      Players.update_player!(player, %{
        daily_matches: 0,
        daily_wins: 0,
        total_wins: total_wins,
        total_matches: total_matches
      })
    end
  end

  def continue_match!(%{winner_id: winner_id, type: type} = match) when not is_nil(winner_id) do
    match = score_match!(match)
    if type != "auto", do: Moba.update_pvp_ranking()

    match
  end

  def continue_match!(match) do
    latest_battle = Engine.latest_match_battle(match.id)
    last_turn = if latest_battle, do: List.last(latest_battle.turns), else: nil
    {attacker, defender} = Matches.get_latest_battlers(match, last_turn)
    battle = Engine.create_match_battle!(%{attacker: attacker, defender: defender, match: match})

    match
    |> Matches.finish!(battle)
    |> continue_match!()
  end

  def create_match!(%{daily_matches: player_matches}, _, _) when player_matches >= @daily_match_limit, do: nil

  def create_match!(%{id: player_id}, %{id: opponent_id}, type) do
    player_picks = Heroes.available_pvp_heroes(player_id) |> Enum.map(& &1.id)
    opponent_picks = Heroes.available_pvp_heroes(opponent_id) |> Enum.map(& &1.id)

    Matches.create!(%{
      player_id: player_id,
      opponent_id: opponent_id,
      player_picks: player_picks,
      opponent_picks: opponent_picks,
      type: type
    })
  end

  def create_pvp_duel!(player, opponent) do
    duel = Duels.create!(player, opponent, "pvp", false)

    Players.set_player_unavailable!(player) && Players.set_player_unavailable!(opponent)

    MobaWeb.broadcast("player-#{player.id}", "duel", %{id: duel.id})
    MobaWeb.broadcast("player-#{opponent.id}", "duel", %{id: duel.id})

    duel
  end

  def duel_challenge(%{id: player_id}, %{id: opponent_id}) do
    attrs = %{player_id: player_id, opponent_id: opponent_id}

    MobaWeb.broadcast("player-#{player_id}", "challenge", attrs)
    MobaWeb.broadcast("player-#{opponent_id}", "challenge", attrs)
  end

  def elite_matchmaking!(player), do: create_matchmaking!(player, Players.matchmaking_opponent(player), false)

  def finish_duel!(%{type: "pvp"} = duel, winner, rewards) do
    Players.set_player_available!(duel.player) && Players.set_player_available!(duel.opponent_player)
    Duels.finish!(duel, winner, rewards)
  end

  def finish_duel!(duel, winner, rewards) do
    unless duel.auto, do: Moba.reward_shards!(duel.player, shard_reward_for(duel))
    Duels.finish!(duel, winner, rewards)
  end

  def next_duel_phase!(duel, hero) do
    updated = Duels.next_phase!(duel, hero)
    hero && Game.update_hero!(hero, %{pvp_last_picked: Timex.now(), pvp_picks: hero.pvp_picks + 1})
    MobaWeb.broadcast("duel-#{duel.id}", "phase", updated.phase)
    updated
  end

  def normal_matchmaking!(player), do: create_matchmaking!(player, Players.matchmaking_opponent(player), false)

  def player_duel_updates!(nil, _, _), do: nil

  def player_duel_updates!(player, duel_type, updates) do
    updated = Players.duel_updates!(player, duel_type, updates)
    Moba.update_pvp_ranking()
    updated
  end

  def update_pvp_ranking!(update_tiers?) do
    if update_tiers?, do: Players.update_ranking_tiers!(), else: Players.update_ranking!()
    MobaWeb.broadcast("player-ranking", "ranking", %{})
  end

  defp create_matchmaking!(_, nil, _), do: nil

  defp create_matchmaking!(player, opponent, auto) do
    type = if opponent.pvp_tier <= player.pvp_tier, do: "normal_matchmaking", else: "elite_matchmaking"
    duel = Duels.create!(player, opponent, type, auto)

    duel
  end

  # TODO: Update season points for player
  defp score_match!(%{phase: phase, player: player} = match) when phase != "scored" do
    winner = if match.winner_id == player.id, do: match.player, else: match.opponent
    _loser = if match.winner_id == player.id, do: match.opponent, else: match.player

    match_attrs = %{total_matches: player.total_matches + 1, daily_matches: player.daily_matches + 1}

    winner_attrs =
      if winner.id == player.id do
        %{total_wins: player.total_wins + 1, daily_wins: player.daily_wins + 1}
      else
        %{}
      end

    Players.update_player!(match.player, Map.merge(match_attrs, winner_attrs))

    Matches.update!(match, %{phase: "scored"})
  end

  defp score_match!(match), do: match

  defp shard_reward_for(%{type: "elite_matchmaking"}), do: Moba.elite_matchmaking_shards()
  defp shard_reward_for(_), do: Moba.normal_matchmaking_shards()
end
