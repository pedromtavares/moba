defmodule Moba.Game.Duels do
  alias Moba.{Repo, Game, Engine}
  alias Game.Schema.Duel
  alias Game.Query.HeroQuery

  import Ecto.Query

  def list_finished(user) do
    query =
      from duel in base_query(user),
        where: duel.phase == "finished"

    Repo.all(query)
  end

  def list_pvp(user) do
    query =
      from duel in base_query(user),
        where: duel.type == "pvp"

    Repo.all(query)
  end

  def list_matchmaking(user) do
    types = ["normal_matchmaking", "elite_matchmaking"]
    query = from duel in base_query(user), where: duel.type in ^types

    Repo.all(query)
  end

  def load(queryable \\ Duel) do
    queryable
    |> preload([
      :user,
      :opponent,
      :winner,
      user_first_pick: ^HeroQuery.load(),
      opponent_first_pick: ^HeroQuery.load(),
      user_second_pick: ^HeroQuery.load(),
      opponent_second_pick: ^HeroQuery.load()
    ])
  end

  def simple_load(queryable \\ Duel) do
    queryable
    |> preload([
      :user,
      :opponent,
      :winner,
      user_first_pick: ^HeroQuery.load_avatar(),
      opponent_first_pick: ^HeroQuery.load_avatar(),
      user_second_pick: ^HeroQuery.load_avatar(),
      opponent_second_pick: ^HeroQuery.load_avatar()
    ])
  end

  def get!(id), do: load() |> Repo.get!(id)

  def create!(user, opponent, type, auto) do
    %Duel{phase: "user_first_pick", auto: auto, user: user, user_id: user.id, opponent_id: opponent.id, type: type}
    |> Duel.changeset(%{phase_changed_at: Timex.now()})
    |> Repo.insert!()
    |> maybe_auto_next_phase()
  end

  def finish!(duel, winner, rewards) do
    update!(duel, %{winner_id: winner && winner.id, rewards: rewards, phase: "finished"})
  end

  def next_phase!(%{phase: phase} = duel, hero) do
    hero_id = hero && Map.get(hero, :id)

    updated =
      case phase do
        "user_first_pick" ->
          update!(duel, %{user_first_pick_id: hero_id, phase: "opponent_first_pick", phase_changed_at: Timex.now()})

        "opponent_first_pick" ->
          updated =
            update!(duel, %{opponent_first_pick_id: hero_id, phase: "user_battle", phase_changed_at: Timex.now()})

          defender = Game.get_hero!(hero_id)
          Engine.create_duel_battle!(%{attacker: duel.user_first_pick, defender: defender, duel_id: duel.id})
          updated

        "user_battle" ->
          update!(duel, %{phase: "opponent_second_pick", phase_changed_at: Timex.now()})

        "opponent_second_pick" ->
          update!(duel, %{opponent_second_pick_id: hero_id, phase: "user_second_pick", phase_changed_at: Timex.now()})

        "user_second_pick" ->
          updated =
            update!(duel, %{user_second_pick_id: hero_id, phase: "opponent_battle", phase_changed_at: Timex.now()})

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

  def auto_next_phase!(%{phase: phase, user_id: user_id} = duel)
      when phase in ["user_first_pick", "user_second_pick"] do
    hero = available_hero(user_id, duel.user_first_pick_id) |> Repo.all() |> List.first()
    Game.next_duel_phase!(get!(duel.id), hero)
  end

  def auto_next_phase!(%{phase: phase, opponent_id: opponent_id} = duel)
      when phase in ["opponent_first_pick", "opponent_second_pick"] do
    hero = available_hero(opponent_id, duel.opponent_first_pick_id) |> Repo.all() |> List.first()
    Game.next_duel_phase!(get!(duel.id), hero)
  end

  def auto_next_phase!(duel), do: duel

  defp available_hero(user_id, nil) do
    HeroQuery.unarchived() |> HeroQuery.with_user(user_id) |> HeroQuery.order_by_pvp() |> HeroQuery.limit_by(1)
  end

  defp available_hero(user_id, hero_id) do
    available_hero(user_id, nil) |> HeroQuery.exclude_ids([hero_id])
  end

  defp base_query(%{id: user_id}) do
    from duel in simple_load(),
      where: duel.user_id == ^user_id or duel.opponent_id == ^user_id,
      limit: 10,
      order_by: [desc: duel.inserted_at]
  end

  defp maybe_auto_next_phase(%{auto: true} = duel), do: auto_next_phase!(duel)

  defp maybe_auto_next_phase(%{user: %{is_bot: true}} = duel), do: auto_next_phase!(duel)

  defp maybe_auto_next_phase(%{phase: phase, type: type} = duel)
       when phase in ["opponent_first_pick", "opponent_second_pick"] and type != "pvp" do
    auto_next_phase!(duel)
  end

  defp maybe_auto_next_phase(duel), do: duel

  defp update!(duel, attrs), do: Duel.changeset(duel, attrs) |> Repo.update!()
end
