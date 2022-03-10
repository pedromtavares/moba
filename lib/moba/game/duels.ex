defmodule Moba.Game.Duels do
  alias Moba.{Repo, Game, Engine}
  alias Game.Schema.Duel
  alias Game.Query.HeroQuery

  import Ecto.Query

  def list(user) do 
    query = 
      from duel in base_query(user),
        where: duel.phase == "finished"

    Repo.all(query)
  end

  def list_matchmaking(user) do
    query = 
      from duel in base_query(user),
        where: duel.type == "normal_matchmaking" or duel.type == "elite_matchmaking"

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

  def get!(id), do: load() |> Repo.get!(id)

  def create!(user, opponent, type) do
    %Duel{phase: "user_first_pick", user_id: user.id, opponent_id: opponent.id, type: type}
    |> Duel.changeset(%{})
    |> Repo.insert!()
  end

  def next_phase!(%{phase: phase} = duel, hero) do
    hero_id = hero && Map.get(hero, :id)

    updated =
      case phase do
        "user_first_pick" ->
          update!(duel, %{user_first_pick_id: hero_id, phase: "opponent_first_pick"})

        "opponent_first_pick" ->
          updated = update!(duel, %{opponent_first_pick_id: hero_id, phase: "user_battle"})
          defender = Game.get_hero!(hero_id)
          Engine.create_duel_battle!(%{attacker: duel.user_first_pick, defender: defender, duel_id: duel.id})
          updated

        "user_battle" ->
          update!(duel, %{phase: "opponent_second_pick"})

        "opponent_second_pick" ->
          update!(duel, %{opponent_second_pick_id: hero_id, phase: "user_second_pick"})

        "user_second_pick" ->
          updated = update!(duel, %{user_second_pick_id: hero_id, phase: "opponent_battle"})
          defender = Game.get_hero!(hero_id)
          Engine.create_duel_battle!(%{attacker: duel.opponent_second_pick, defender: defender, duel_id: duel.id})
          updated

        "opponent_battle" ->
          update!(duel, %{phase: "finished"})

        _ ->
          duel
      end

    maybe_auto_next_phase(updated)
  end

  def finish!(duel, winner, rewards) do
    update!(duel, %{winner_id: winner && winner.id, rewards: rewards, phase: "finished"})
  end

  defp available_bot_hero(%{opponent: %{id: user_id}, inserted_at: duel_inserted_at}) do
    Game.eligible_heroes_for_pvp(user_id, duel_inserted_at)
    |> List.first()
  end

  defp base_query(%{id: user_id}) do
    from duel in load(),
      where: duel.user_id == ^user_id,
      limit: 20,
      order_by: [desc: duel.inserted_at]
  end

  defp maybe_auto_next_phase(%{opponent: %{is_bot: true}, phase: phase} = duel)
       when phase in ["opponent_first_pick", "opponent_second_pick"] do
    Game.next_duel_phase!(get!(duel.id), available_bot_hero(duel))
  end

  defp maybe_auto_next_phase(duel), do: duel

  defp update!(duel, attrs), do: Duel.changeset(duel, attrs) |> Repo.update!()
end
