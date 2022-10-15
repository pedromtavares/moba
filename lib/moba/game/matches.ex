defmodule Moba.Game.Matches do
  alias Moba.{Game, Repo}
  alias Game.Schema.Match

  import Ecto.Query

  def create!(attrs), do: Match.changeset(%Match{}, attrs) |> Repo.insert!()

  def finished?(%{winner: winner}, _) when not is_nil(winner), do: winner
  def finished?(_, nil), do: false

  def finished?(%{player_picks: player_picks, opponent_picks: opponent_picks} = match, latest_battle) do
    last_player_pick = List.last(player_picks)
    last_opponent_pick = List.last(opponent_picks)

    cond do
      hero_loser?(last_player_pick, latest_battle) -> match.opponent
      hero_loser?(last_opponent_pick, latest_battle) -> match.player
      true -> false
    end
  end

  def get_latest_battlers(%{player_picks: player_picks, opponent_picks: opponent_picks}, nil) do
    {List.first(player_picks), List.first(opponent_picks)}
  end

  def get_latest_battlers(%{player_picks: player_picks, opponent_picks: opponent_picks}, last_turn) do
    winner = if last_turn.attacker.current_hp > 0, do: last_turn.attacker, else: last_turn.defender
    loser = if winner == last_turn.attacker, do: last_turn.defender, else: last_turn.attacker

    winner_is_player_pick = Enum.find(player_picks, &(&1.id == winner.hero_id))

    {attacker_pick, defender_pick} =
      if winner_is_player_pick do
        opponent_loser_index = Enum.find_index(opponent_picks, &(&1.id == loser.hero_id))

        {winner_is_player_pick, Enum.at(opponent_picks, opponent_loser_index + 1)}
      else
        winner_is_opponent_pick = Enum.find(opponent_picks, &(&1.id == winner.hero_id))
        player_loser_index = Enum.find_index(player_picks, &(&1.id == loser.hero_id))

        {winner_is_opponent_pick, Enum.at(player_picks, player_loser_index + 1)}
      end

    attacker_pick =
      attacker_pick
      |> Map.put(:initial_hp, winner.current_hp + winner.total_hp * 0.2)
      |> Map.put(:initial_mp, winner.current_mp + winner.total_mp * 0.2)

    {attacker_pick, defender_pick}
  end

  def get_match!(id), do: load() |> Repo.get!(id) |> load_picks()

  def load(queryable \\ Match) do
    preload(queryable, player: :user, opponent: :user, winner: :user)
  end

  def update!(match, attrs), do: Match.changeset(match, attrs) |> Repo.update!()

  defp hero_loser?(pick, %{winner: winner} = _battle) when is_nil(winner), do: false
  defp hero_loser?(%{id: pick_id}, %{winner_id: winner_id}) when pick_id == winner_id, do: false
  defp hero_loser?(%{id: pid}, %{attacker_id: aid, defender_id: did}) when pid != aid and pid != did, do: false
  defp hero_loser?(_, _), do: true

  defp load_picks(%{player_picks: player_picks, opponent_picks: opponent_picks} = match) do
    heroes = Game.get_heroes(player_picks ++ opponent_picks)
    player_picks = Enum.map(player_picks, &load_picks_hero(heroes, &1))
    opponent_picks = Enum.map(opponent_picks, &load_picks_hero(heroes, &1))

    %{match | player_picks: player_picks, opponent_picks: opponent_picks}
  end

  defp load_picks_hero(heroes, hero_id), do: Enum.find(heroes, &(&1.id == hero_id))
end
