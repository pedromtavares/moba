defmodule Moba.Game.Duels do
  alias Moba.{Repo, Game, Engine}
  alias Game.Schema.Duel
  alias Game.Query.HeroQuery

  import Ecto.Query

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

  def create!(user, opponent) do
    %Duel{phase: "user_first_pick", user_id: user.id, opponent_id: opponent.id}
    |> Duel.changeset(%{})
    |> Repo.insert!()
  end

  def next_phase!(%{phase: phase} = duel, hero_id) do
    case phase do
      "user_first_pick" ->
        update!(duel, %{user_first_pick_id: hero_id, phase: "opponent_first_pick"})

      "opponent_first_pick" ->
        updated = update!(duel, %{opponent_first_pick_id: hero_id, phase: "user_battle"})
        defender = Game.get_hero!(hero_id) |> Game.prepare_hero_for_pvp!()
        Engine.create_duel_battle!(%{attacker: duel.user_first_pick, defender: defender, duel_id: duel.id})
        updated

      "user_battle" ->
        update!(duel, %{phase: "opponent_second_pick"})

      "opponent_second_pick" ->
        update!(duel, %{opponent_second_pick_id: hero_id, phase: "user_second_pick"})

      "user_second_pick" ->
        updated = update!(duel, %{user_second_pick_id: hero_id, phase: "opponent_battle"})
        defender = Game.get_hero!(hero_id) |> Game.prepare_hero_for_pvp!()
        Engine.create_duel_battle!(%{attacker: duel.opponent_second_pick, defender: defender, duel_id: duel.id})
        updated

      "opponent_battle" ->
        update!(duel, %{phase: "finished"})

      _ ->
        duel
    end
  end

  def finish!(duel, winner, rewards) do
    update!(duel, %{winner_id: winner && winner.id, rewards: rewards, phase: "finished"})
  end

  defp update!(duel, attrs), do: Duel.changeset(duel, attrs) |> Repo.update!()
end
