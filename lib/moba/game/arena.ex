defmodule Moba.Game.Arena do
  @moduledoc """
  Module focused on cross-domain orchestration and logic related to PvP (Duels & Matchmaking)
  """
  alias Moba.{Accounts, Game}
  alias Game.Duels

  def auto_next_duel_phase!(duel) do
    updated = Duels.auto_next_phase!(duel)
    MobaWeb.broadcast("duel-#{duel.id}", "phase", updated.phase)
    updated
  end

  def create_matchmaking!(_, nil, _), do: nil

  def create_matchmaking!(user, opponent, auto) do
    type = if opponent.season_tier <= user.season_tier, do: "normal_matchmaking", else: "elite_matchmaking"
    duel = Duels.create!(user, opponent, type, auto)

    Accounts.manage_match_history(user, opponent)

    duel
  end

  def create_pvp_duel!(user, opponent) do
    duel = Duels.create!(user, opponent, "pvp", false)

    Accounts.set_unavailable!(user) && Accounts.set_unavailable!(opponent)

    MobaWeb.broadcast("user-#{user.id}", "duel", %{id: duel.id})
    MobaWeb.broadcast("user-#{opponent.id}", "duel", %{id: duel.id})

    duel
  end

  def duel_challenge(%{id: user_id}, %{id: opponent_id}) do
    attrs = %{user_id: user_id, opponent_id: opponent_id}

    MobaWeb.broadcast("user-#{user_id}", "challenge", attrs)
    MobaWeb.broadcast("user-#{opponent_id}", "challenge", attrs)
  end

  def finish_duel!(%{type: "pvp"} = duel, winner, rewards) do
    Accounts.set_available!(duel.user) && Accounts.set_available!(duel.opponent)
    Duels.finish!(duel, winner, rewards)
  end

  def finish_duel!(duel, winner, rewards), do: Duels.finish!(duel, winner, rewards)

  def next_duel_phase!(duel, hero) do
    updated = Duels.next_phase!(duel, hero)
    hero && Game.update_hero!(hero, %{pvp_last_picked: Timex.now(), pvp_picks: hero.pvp_picks + 1})
    MobaWeb.broadcast("duel-#{duel.id}", "phase", updated.phase)
    updated
  end
end
