defmodule Moba.Game.Arena do
  @moduledoc """
  Module focused on cross-resource orchestration and logic related to PvP (Duels & Matchmaking)
  """
  alias Moba.{Engine, Game}
  alias Game.{Duels, Heroes, Matches, Players}

  @daily_match_limit 30

  def auto_matchmaking!(player), do: create_match!(player, Players.matchmaking_opponent(player), "auto")

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

  def continue_duel!(%{phase: "opponent_battle"} = duel, _) do
    score = score_duel!(duel)
    Players.set_player_available!(duel.player) && Players.set_player_available!(duel.opponent_player)
    Duels.finish!(duel, score)
  end

  def continue_duel!(duel, hero) do
    updated = if hero == :auto, do: Duels.auto_next_phase!(duel), else: Duels.next_phase!(duel, hero)
    hero && hero != :auto && Game.update_hero!(hero, %{pvp_last_picked: Timex.now(), pvp_picks: hero.pvp_picks + 1})
    MobaWeb.broadcast("duel-#{duel.id}", "phase", updated.phase)
    updated
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

  def create_duel!(player, opponent) do
    duel = Duels.create!(player, opponent)

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

  def update_pvp_ranking!(update_tiers?) do
    if update_tiers?, do: Players.update_ranking_tiers!(), else: Players.update_ranking!()
    MobaWeb.broadcast("player-ranking", "ranking", %{})
  end

  defp score_duel!(%{phase: "opponent_battle", player: player, opponent_player: opponent} = duel) do
    %{winner_id: first_winner_id} = Engine.first_duel_battle(duel)
    %{winner_id: last_winner_id} = Engine.last_duel_battle(duel)

    player_win = first_winner_id == duel.player_first_pick_id && last_winner_id == duel.player_second_pick_id

    opponent_win = first_winner_id == duel.opponent_first_pick_id && last_winner_id == duel.opponent_second_pick_id

    winner =
      cond do
        player_win -> player
        opponent_win -> opponent
        true -> nil
      end

    {player_points, opponent_points} = Duels.pvp_points(player, opponent, winner)
    player_updates = if player_win, do: %{loser_id: opponent.id}, else: %{}
    opponent_updates = if opponent_win, do: %{loser_id: player.id}, else: %{}

    Players.duel_update!(player, Map.merge(player_updates, %{pvp_points: player_points}))
    Players.duel_update!(opponent, Map.merge(opponent_updates, %{pvp_points: opponent_points}))

    Moba.update_pvp_ranking()

    %{winner: winner, attacker_pvp_points: player_points, defender_pvp_points: opponent_points}
  end

  defp score_duel!(_), do: %{}

  defp score_match!(%{phase: phase, player: player, opponent: opponent} = match) when phase != "scored" do
    winner = if match.winner_id == player.id, do: player, else: opponent
    _loser = if match.winner_id == player.id, do: opponent, else: player

    {player_points, _} = Duels.pvp_points(player, opponent, winner)

    match_attrs = %{
      total_matches: player.total_matches + 1,
      daily_matches: player.daily_matches + 1,
      pvp_points: player.pvp_points + player_points
    }

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
end
