defmodule Moba.Game.Duels do
  alias Moba.{Repo, Game, Engine}
  alias Game.Schema.Duel
  alias Game.Query.HeroQuery

  import Ecto.Query

  def auto_next_phase!(%{phase: phase, player: player} = duel)
      when phase in ["player_first_pick", "player_second_pick"] do
    hero = available_hero(player, duel.player_first_pick_id)
    if hero, do: Game.continue_duel!(get_duel!(duel.id), hero)
  end

  def auto_next_phase!(%{phase: phase, opponent_player: opponent} = duel)
      when phase in ["opponent_first_pick", "opponent_second_pick"] do
    hero = available_hero(opponent, duel.opponent_first_pick_id)
    if hero, do: Game.continue_duel!(get_duel!(duel.id), hero)
  end

  def auto_next_phase!(duel), do: duel

  def create!(player, opponent) do
    %Duel{
      phase: "player_first_pick",
      player: player,
      player_id: player.id,
      opponent_player_id: opponent.id
    }
    |> Duel.changeset(%{phase_changed_at: Timex.now()})
    |> Repo.insert!()
  end

  def finish!(duel, %{winner: winner} = score) do
    update!(duel, %{winner_player_id: winner && winner.id, rewards: Map.delete(score, :winner), phase: "finished"})
  end

  def finish!(duel, _), do: duel

  def get_duel!(id), do: load() |> Repo.get!(id)

  def list_finished_duels(player) do
    query =
      from duel in base_query(player),
        where: duel.phase == "finished"

    Repo.all(query)
  end

  def list_duels(player) do
    Repo.all(from(duel in base_query(player)))
  end

  def load(queryable \\ Duel) do
    queryable
    |> preload(
      player: :user,
      opponent_player: :user,
      winner_player: :user,
      player_first_pick: ^HeroQuery.load(),
      opponent_first_pick: ^HeroQuery.load(),
      player_second_pick: ^HeroQuery.load(),
      opponent_second_pick: ^HeroQuery.load()
    )
  end

  def load_less(queryable \\ Duel) do
    queryable
    |> preload(
      player: :user,
      opponent_player: :user,
      winner_player: :user,
      player_first_pick: ^HeroQuery.load_avatar(),
      opponent_first_pick: ^HeroQuery.load_avatar(),
      player_second_pick: ^HeroQuery.load_avatar(),
      opponent_second_pick: ^HeroQuery.load_avatar()
    )
  end

  def next_phase!(%{phase: phase} = duel, hero) do
    hero_id = hero && Map.get(hero, :id)

    case phase do
      "player_first_pick" ->
        update!(duel, %{player_first_pick_id: hero_id, phase: "opponent_first_pick", phase_changed_at: Timex.now()})

      "opponent_first_pick" ->
        updated =
          update!(duel, %{opponent_first_pick_id: hero_id, phase: "player_battle", phase_changed_at: Timex.now()})

        defender = Game.get_hero!(hero_id)
        Engine.create_duel_battle!(%{attacker: duel.player_first_pick, defender: defender, duel_id: duel.id})
        updated

      "player_battle" ->
        update!(duel, %{phase: "opponent_second_pick", phase_changed_at: Timex.now()})

      "opponent_second_pick" ->
        update!(duel, %{opponent_second_pick_id: hero_id, phase: "player_second_pick", phase_changed_at: Timex.now()})

      "player_second_pick" ->
        updated =
          update!(duel, %{player_second_pick_id: hero_id, phase: "opponent_battle", phase_changed_at: Timex.now()})

        defender = Game.get_hero!(hero_id)
        Engine.create_duel_battle!(%{attacker: duel.opponent_second_pick, defender: defender, duel_id: duel.id})
        updated

      _ ->
        duel
    end
  end

  def pvp_points(player, opponent, winner, skip_victory_limit \\ false) do
    diff = opponent.pvp_points - player.pvp_points
    victory_points = Moba.victory_duel_points(diff, skip_victory_limit)
    defeat_points = Moba.defeat_duel_points(diff)
    tie_points = Moba.tie_duel_points(diff)

    {player_points, opponent_points} =
      cond do
        winner && player.id == winner.id ->
          {victory_points, victory_points * -1}

        winner && opponent.id == winner.id ->
          {defeat_points * -1, defeat_points}

        true ->
          {tie_points, tie_points * -1}
      end

    %{
      total_player_points: points_limits(player.pvp_points + player_points),
      player_points: player_points,
      total_opponent_points: points_limits(opponent.pvp_points + opponent_points),
      opponent_points: opponent_points
    }
  end

  defp available_hero(player, pick_id) do
    available_heroes(player, pick_id) |> List.first()
  end

  defp available_heroes(player, nil), do: Game.available_pvp_heroes(player, [])
  defp available_heroes(player, hero_id), do: Game.available_pvp_heroes(player, [hero_id])

  defp base_query(%{id: player_id}, limit \\ 15) do
    from duel in load_less(),
      where: duel.player_id == ^player_id or duel.opponent_player_id == ^player_id,
      limit: ^limit,
      where: is_nil(duel.type) or duel.type == "pvp",
      order_by: [desc: duel.inserted_at]
  end

  defp points_limits(result) when result < 0, do: 0
  defp points_limits(result), do: result

  defp update!(duel, attrs), do: Duel.changeset(duel, attrs) |> Repo.update!()
end
