defmodule Moba.Game.Matches do
  alias Moba.{Game, Repo}
  alias Game.Schema.Match

  import Ecto.Query

  @types %{manual: "manual", auto: "auto"}

  def create!(attrs), do: Match.changeset(%Match{}, attrs) |> Repo.insert!()

  # prioritizes deleting losses first
  def delete_oldest_auto(%{id: player_id}) do
    query = list_query(player_id, "auto") |> exclude(:order_by) |> exclude(:preload)

    from(m in query, order_by: [desc: fragment("? = ?", m.winner_id, m.opponent_id), asc: :id], limit: 1)
    |> Repo.one()
    |> Repo.delete!()
  end

  def finish!(%{winner_id: winner_id} = match, _) when not is_nil(winner_id), do: match
  def finish!(match, nil), do: match

  def finish!(match, last_battle) do
    winner = last_winner(match, last_battle)

    if winner do
      update!(match, %{winner_id: winner.id, phase: "finished"})
    else
      update!(match, %{phase: "started"})
    end
  end

  def get_latest_battlers(match, _, nil) do
    attacker = %{hero: List.first(match.player_picks), player: match.player, position: 0}
    defender = %{hero: List.first(match.opponent_picks), player: match.opponent, position: 0}
    {attacker, defender}
  end

  def get_latest_battlers(match, battle, last_turn) do
    %{player: player, player_picks: player_picks, opponent: opponent, opponent_picks: opponent_picks} = match
    %{winner_player: winner_player} = battle

    winner = if last_turn.attacker.current_hp > 0, do: last_turn.attacker, else: last_turn.defender
    loser = if winner == last_turn.attacker, do: last_turn.defender, else: last_turn.attacker

    winner_is_player_pick = winner_player.id == player.id && Enum.find(player_picks, &(&1.id == winner.hero_id))

    {attacker, defender} =
      if winner_is_player_pick do
        winner_pick_index = Enum.find_index(player_picks, &(&1.id == winner_is_player_pick.id))
        opponent_loser_index = Enum.find_index(opponent_picks, &(&1.id == loser.hero_id)) || 0
        next_opponent_pick = Enum.at(opponent_picks, opponent_loser_index + 1)

        attacker = %{hero: winner_is_player_pick, player: player, position: winner_pick_index}
        defender = %{hero: next_opponent_pick, player: opponent, position: opponent_loser_index + 1}

        {attacker, defender}
      else
        winner_is_opponent_pick = Enum.find(opponent_picks, &(&1.id == winner.hero_id))
        winner_pick_index = Enum.find_index(opponent_picks, &(&1.id == winner.hero_id))
        player_loser_index = Enum.find_index(player_picks, &(&1.id == loser.hero_id)) || 0
        next_player_pick = Enum.at(player_picks, player_loser_index + 1)

        attacker = %{hero: winner_is_opponent_pick, player: opponent, position: winner_pick_index}
        defender = %{hero: next_player_pick, player: player, position: player_loser_index + 1}

        {attacker, defender}
      end

    attacker_pick =
      attacker.hero
      |> Map.put(:initial_hp, winner.current_hp + winner.total_hp * 0.2)
      |> Map.put(:initial_mp, winner.current_mp + winner.total_mp * 0.2)

    {
      %{attacker | hero: attacker_pick},
      defender
    }
  end

  def get_match!(id), do: load() |> Repo.get!(id) |> load_picks()

  def latest_manual_match(%{id: player_id}) do
    from(m in list_query(player_id, "manual"), limit: 1, where: fragment("? != '[]'", m.player_picks))
    |> Repo.all()
    |> List.first()
    |> load_picks()
  end

  def list_matches(%{id: player_id}), do: list_query(player_id) |> Repo.all()

  def list_manual(%{id: player_id}), do: list_query(player_id, "manual") |> Repo.all()

  def load(queryable \\ Match) do
    preload(queryable, player: :user, opponent: :user, winner: :user)
  end

  def types, do: @types

  def update!(match, attrs), do: Match.changeset(match, attrs) |> Repo.update!()

  defp last_winner(match, battle) do
    battle_attacker_is_match_player = battle.attacker_player_id == match.player_id

    cond do
      battle_attacker_is_match_player && battle.winner_player_id == battle.attacker_player_id &&
          battle.defender_pick_position == 4 ->
        match.player

      battle_attacker_is_match_player && battle.winner_player_id == battle.defender_player_id &&
          battle.attacker_pick_position == 4 ->
        match.opponent

      !battle_attacker_is_match_player && battle.winner_player_id == battle.attacker_player_id &&
        battle.defender_pick_position == 4 ->
          match.opponent

      !battle_attacker_is_match_player && battle.winner_player_id == battle.defender_player_id &&
          battle.attacker_pick_position == 4 ->
        match.player

      true ->
        false
    end
  end

  defp list_query(player_id, type \\ nil) do
    season = Moba.current_season()

    from(match in load(),
      where: match.player_id == ^player_id,
      where: match.inserted_at > ^season.last_pvp_update_at,
      order_by: [desc: :id]
    )
    |> type_query(type)
  end

  defp load_picks(
         %{player_picks: player_picks, opponent_picks: opponent_picks, generated_picks: generated_picks} = match
       ) do
    heroes = Game.get_heroes(player_picks ++ opponent_picks ++ generated_picks)
    player_picks = Enum.map(player_picks, &load_picks_hero(heroes, &1))
    opponent_picks = Enum.map(opponent_picks, &load_picks_hero(heroes, &1))
    generated_picks = Enum.map(generated_picks, &load_picks_hero(heroes, &1))

    %{match | player_picks: player_picks, opponent_picks: opponent_picks, generated_picks: generated_picks}
  end

  defp load_picks(_), do: nil

  defp load_picks_hero(heroes, hero_id), do: Enum.find(heroes, &(&1.id == hero_id))

  defp type_query(query, nil), do: query

  defp type_query(query, type) do
    from(match in query, where: match.type == ^type)
  end
end
