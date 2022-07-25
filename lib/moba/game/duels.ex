defmodule Moba.Game.Duels do
  alias Moba.{Repo, Game, Engine}
  alias Game.Schema.Duel
  alias Game.Query.HeroQuery

  import Ecto.Query

  def list_finished_duels(player) do
    query =
      from duel in base_query(player),
        where: duel.phase == "finished"

    Repo.all(query)
  end

  def list_pvp_duels(player) do
    query =
      from duel in base_query(player),
        where: duel.type == "pvp"

    Repo.all(query)
  end

  def list_matchmaking(player) do
    types = ["normal_matchmaking", "elite_matchmaking"]
    query = from duel in base_query(player), where: duel.type in ^types

    Repo.all(query)
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

  def simple_load(queryable \\ Duel) do
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

  def get_duel!(id), do: load() |> Repo.get!(id)

  def create!(player, opponent, type, auto) do
    %Duel{
      phase: "player_first_pick",
      auto: auto,
      player: player,
      player_id: player.id,
      opponent_player_id: opponent.id,
      type: type
    }
    |> Duel.changeset(%{phase_changed_at: Timex.now()})
    |> Repo.insert!()
    |> maybe_auto_next_phase()
  end

  def finish!(duel, winner, rewards) do
    update!(duel, %{winner_player_id: winner && winner.id, rewards: rewards, phase: "finished"})
  end

  def next_phase!(%{phase: phase} = duel, hero) do
    hero_id = hero && Map.get(hero, :id)

    updated =
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

        "opponent_battle" ->
          update!(duel, %{phase: "finished", phase_changed_at: Timex.now()})

        _ ->
          duel
      end

    maybe_auto_next_phase(updated)
  end

  def auto_next_phase!(%{phase: phase, player_id: player_id} = duel)
      when phase in ["player_first_pick", "player_second_pick"] do
    hero = available_random_hero(player_id, duel.player_first_pick_id)
    if hero, do: Game.next_duel_phase!(get_duel!(duel.id), hero)
  end

  def auto_next_phase!(%{phase: phase, opponent_player_id: opponent_id} = duel)
      when phase in ["opponent_first_pick", "opponent_second_pick"] do
    hero = available_random_hero(opponent_id, duel.opponent_first_pick_id)
    if hero, do: Game.next_duel_phase!(get_duel!(duel.id), hero)
  end

  def auto_next_phase!(duel), do: duel

  defp available_random_hero(player_id, pick_id) do
    available_hero(player_id, pick_id) |> Repo.all() |> Enum.shuffle() |> List.first()
  end

  defp available_hero(player_id, nil) do
    HeroQuery.unarchived() |> HeroQuery.with_player(player_id) |> HeroQuery.order_by_pvp() |> HeroQuery.limit_by(5)
  end

  defp available_hero(player_id, hero_id) do
    available_hero(player_id, nil) |> HeroQuery.exclude_ids([hero_id])
  end

  defp base_query(%{id: player_id}) do
    from duel in simple_load(),
      where: duel.player_id == ^player_id or duel.opponent_player_id == ^player_id,
      limit: 12,
      order_by: [desc: duel.inserted_at]
  end

  defp maybe_auto_next_phase(%{auto: true} = duel), do: auto_next_phase!(duel)

  defp maybe_auto_next_phase(%{phase: phase, type: type} = duel)
       when phase in ["opponent_first_pick", "opponent_second_pick"] and type != "pvp" do
    auto_next_phase!(duel)
  end

  defp maybe_auto_next_phase(duel), do: duel

  defp update!(duel, attrs), do: Duel.changeset(duel, attrs) |> Repo.update!()
end
