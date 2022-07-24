defmodule Moba.Game.Arena do
  @moduledoc """
  Module focused on cross-resource orchestration and logic related to PvP (Duels & Matchmaking)
  """
  alias Moba.Game
  alias Game.{Duels, Players}

  def auto_matchmaking!(player), do: create_matchmaking!(player, Players.matchmaking_opponent(player), true)

  def auto_next_duel_phase!(duel) do
    updated = Duels.auto_next_phase!(duel)
    MobaWeb.broadcast("duel-#{duel.id}", "phase", updated.phase)
    updated
  end

  def bot_matchmaking!(player), do: create_matchmaking!(player, Players.bot_opponent(player), false)

  def create_pvp_duel!(player, opponent) do
    duel = Duels.create!(player, opponent, "pvp", false)

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

  def elite_matchmaking!(player), do: create_matchmaking!(player, Players.elite_matchmaking_opponent(player), false)

  def finish_duel!(%{type: "pvp"} = duel, winner, rewards) do
    Players.set_player_available!(duel.player) && Players.set_player_available!(duel.opponent_player)
    Duels.finish!(duel, winner, rewards)
  end

  def finish_duel!(duel, winner, rewards) do
    unless duel.auto, do: Moba.reward_shards!(duel.player, shard_reward_for(duel))
    Duels.finish!(duel, winner, rewards)
  end

  def next_duel_phase!(duel, hero) do
    updated = Duels.next_phase!(duel, hero)
    hero && Game.update_hero!(hero, %{pvp_last_picked: Timex.now(), pvp_picks: hero.pvp_picks + 1})
    MobaWeb.broadcast("duel-#{duel.id}", "phase", updated.phase)
    updated
  end

  def normal_matchmaking!(player), do: create_matchmaking!(player, Players.normal_matchmaking_opponent(player), false)

  def player_duel_updates!(nil, _, _), do: nil

  def player_duel_updates!(player, duel_type, updates) do
    updated = Players.duel_updates!(player, duel_type, updates)
    Moba.update_pvp_ranking()
    updated
  end

  def update_pvp_ranking! do
    Players.update_ranking!()
    MobaWeb.broadcast("player-ranking", "ranking", %{})
  end

  defp create_matchmaking!(_, nil, _), do: nil

  defp create_matchmaking!(player, opponent, auto) do
    type = if opponent.pvp_tier <= player.pvp_tier, do: "normal_matchmaking", else: "elite_matchmaking"
    duel = Duels.create!(player, opponent, type, auto)

    Players.manage_match_history(player, opponent)

    duel
  end

  defp shard_reward_for(%{type: "elite_matchmaking"}), do: Moba.elite_matchmaking_shards()
  defp shard_reward_for(_), do: Moba.normal_matchmaking_shards()
end
