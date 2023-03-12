defmodule Moba.Game.Arena do
  @moduledoc """
  Module focused on cross-resource orchestration and logic related to PvP (Duels & Matchmaking)
  """
  alias Moba.{Engine, Game}
  alias Game.{Duels, Heroes, Matches, Players, Teams}

  @daily_match_limit Moba.daily_match_limit()

  def auto_matchmaking!(player), do: create_match!(player, Players.matchmaking_opponent(player), "auto")

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

  def continue_match!(match, player_picks) do
    Matches.update!(match, %{player_picks: player_picks})
    Matches.get_match!(match.id) |> continue_match!()
  end

  def continue_match!(%{winner_id: winner_id, type: type} = match) when not is_nil(winner_id) do
    match = score_match!(match)
    if type != "auto", do: Moba.update_pvp_rankings()

    match
  end

  def continue_match!(match) do
    latest_battle = Engine.latest_match_battle(match.id)
    last_turn = if latest_battle, do: List.last(latest_battle.turns), else: nil

    {attacker, defender} = Matches.get_latest_battlers(match, latest_battle, last_turn)

    battle =
      Engine.create_match_battle!(%{
        attacker: attacker.hero,
        attacker_player: attacker.player,
        attacker_pick_position: attacker.position,
        defender: defender.hero,
        defender_player: defender.player,
        defender_pick_position: defender.position,
        match: match
      })

    match
    |> Matches.finish!(battle)
    |> continue_match!()
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

  def manual_matchmaking!(player) do
    match = create_match!(player, Players.matchmaking_opponent(player), "manual")
    if match, do: Moba.reward_shards!(player, Moba.matchmaking_shards())
    match
  end

  def reset_match!(%{id: id} = match) do
    Engine.delete_match_battles!(match)

    Matches.get_match!(id)
    |> Matches.update!(%{winner_id: nil, phase: nil, player_picks: []})
  end

  def update_daily_ranking!(update_tiers?) do
    if update_tiers?, do: Players.update_ranking_tiers!(), else: Players.update_ranking!()
  end

  defp create_match!(%{daily_matches: count} = player, opponent, "manual") when count >= @daily_match_limit do
    manual_matches = Matches.list_manual(player)

    if length(manual_matches) >= @daily_match_limit do
      nil
    else
      deleted = Matches.delete_oldest_auto(player)
      base_attrs = %{daily_matches: player.daily_matches - 1, total_matches: player.total_matches - 1}

      attrs =
        if deleted.winner_id == player.id do
          Map.merge(base_attrs, %{daily_wins: player.daily_wins - 1, total_wins: player.total_wins - 1})
        else
          base_attrs
        end

      player
      |> Players.update_player!(attrs)
      |> create_match!(opponent, "manual")
    end
  end

  defp create_match!(%{daily_matches: player_matches}, _, _) when player_matches >= @daily_match_limit, do: nil

  defp create_match!(%{id: player_id, pvp_tier: pvp_tier}, %{id: opponent_id}, type) do
    bot_ids = Enum.map(Heroes.pvp_bots(), & &1.id)
    player_pick_id = if type == "manual", do: nil, else: player_id

    Matches.create!(%{
      player_id: player_id,
      opponent_id: opponent_id,
      player_picks: match_picks(player_pick_id, pvp_tier, bot_ids, false),
      opponent_picks: match_picks(opponent_id, pvp_tier, bot_ids, true),
      generated_picks: bot_ids,
      type: type
    })
  end

  defp create_match!(_, _, _), do: nil

  defp match_picks(nil, _, _, _), do: []

  defp match_picks(player_id, 0, bot_ids, defensive) do
    team = Teams.list_teams(player_id, defensive) |> Enum.shuffle() |> List.first()

    pick_ids =
      if team do
        Enum.take(team.pick_ids, 5)
      else
        Heroes.trained_pvp_heroes(player_id) |> Enum.map(& &1.id)
      end

    diff = 5 - length(pick_ids)

    if diff > 0 do
      generated_ids = Enum.shuffle(bot_ids) |> Enum.take(diff)
      pick_ids ++ generated_ids
    else
      pick_ids
    end
  end

  defp match_picks(player_id, _, bot_ids, defensive) do
    team = Teams.list_teams(player_id, defensive) |> Enum.shuffle() |> List.first()

    pick_ids =
      if team do
        Enum.take(team.pick_ids, 5)
      else
        trained = Heroes.trained_pvp_heroes(player_id)
        first = List.first(trained)
        others = trained -- [first]
        first_id = if first, do: first.id, else: nil

        grandmasters =
          others
          |> Enum.filter(&(&1.league_tier == Moba.max_league_tier()))
          |> Enum.map(& &1.id)

        if first_id, do: grandmasters ++ [first_id], else: grandmasters
      end

    diff = 5 - length(pick_ids)

    if diff > 0 do
      available_ids = Enum.shuffle(bot_ids) |> Enum.take(diff)
      pick_ids ++ available_ids
    else
      pick_ids
    end
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

    duel_points = Duels.pvp_points(player, opponent, winner)
    player_updates = if player_win, do: %{loser_id: opponent.id}, else: %{}
    opponent_updates = if opponent_win, do: %{loser_id: player.id}, else: %{}

    Players.duel_update!(player, Map.merge(player_updates, %{pvp_points: duel_points.total_player_points}))
    Players.duel_update!(opponent, Map.merge(opponent_updates, %{pvp_points: duel_points.total_opponent_points}))

    Moba.update_pvp_rankings()

    %{winner: winner, attacker_pvp_points: duel_points.player_points, defender_pvp_points: duel_points.opponent_points}
  end

  defp score_duel!(_), do: %{}

  defp score_match!(%{phase: phase, player: player, opponent: opponent} = match) when phase != "scored" do
    winner = if match.winner_id == player.id, do: player, else: opponent
    _loser = if match.winner_id == player.id, do: opponent, else: player

    pvp_points = Duels.pvp_points(player, opponent, winner, true)

    match_attrs = %{
      total_matches: player.total_matches + 1,
      daily_matches: player.daily_matches + 1,
      pvp_points: pvp_points.total_player_points
    }

    winner_attrs =
      if winner.id == player.id do
        %{total_wins: player.total_wins + 1, daily_wins: player.daily_wins + 1}
      else
        %{}
      end

    Players.update_player!(match.player, Map.merge(match_attrs, winner_attrs))

    Matches.update!(match, %{phase: "scored", rewards: %{attacker_pvp_points: pvp_points.player_points}})
  end

  defp score_match!(match), do: match
end
