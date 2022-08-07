defmodule Moba.Game.Quests do
  @moduledoc """
  Manages tracking of player PVE progression
  """

  alias Moba.Game
  alias Game.Schema.PveProgression

  @platinum_league_tier Moba.platinum_league_tier()

  @all %{
    1 => %{
      title: "Novice",
      description: "Finish training with 2 different Avatars on the Platinum League or above",
      training_bonus: "+1000 starting gold (1000 -> 2000)",
      difficulty: "3 Easy targets + 6 Medium targets",
      max_league: "Master League",
      prize: 200,
      goal: 2,
      field: :season_codes
    },
    2 => %{
      title: "Adept",
      description: "Finish training with 5 different Avatars on the Platinum League or above",
      difficulty: "6 Medium targets + 3 Hard targets",
      prize: 300,
      goal: 5,
      field: :season_codes
    },
    3 => %{
      title: "Veteran",
      description: "Finish training with 10 different Avatars on the Platinum League or above",
      difficulty: "3 Medium targets + 6 Hard targets",
      prize: 400,
      goal: 10,
      field: :season_codes
    },
    4 => %{
      title: "Expert",
      description: "Finish training with 15 different Avatars on the Platinum League or above",
      training_bonus: "Ability to refresh Targets up to 5 times",
      prize: 500,
      goal: 15,
      field: :season_codes
    },
    5 => %{
      title: "Master",
      description: "Finish training with all Avatars on the Master League or above",
      training_bonus: "Ability to refresh Targets up to 10 times",
      prize: 1000,
      goal: 20,
      field: :master_codes
    },
    6 => %{
      title: "Grandmaster",
      description: "Finish training with all Avatars on the Grandmaster League",
      training_bonus: "Ability to refresh Targets up to 15 times",
      prize: 2500,
      goal: 20,
      field: :grandmaster_codes
    },
    7 => %{
      title: "Invoker",
      description: "Finish training with all avatars in the Grandmaster League with a perfect 60K of total farm",
      difficulty: "9 Hard targets",
      max_league: "Grandmaster League",
      prize: 5000,
      goal: 20,
      field: :invoker_codes
    }
  }

  def get_quest(tier), do: @all[tier]

  def last_completed_quest(%{player: %{pve_progression: %{history: history}, pve_tier: current_tier}} = hero) do
    with {tier, _} <- find_quest_history(history, current_tier, hero) do
      get_quest(String.to_integer(tier))
    else
      _ -> nil
    end
  end

  def track_pve_progression!(%{player: player, league_tier: league_tier, avatar: %{code: avatar_code}} = hero)
      when league_tier >= @platinum_league_tier do
    progression = player.pve_progression || %PveProgression{}

    updates =
      progression
      |> track(:season_codes, avatar_code, true)
      |> track(:master_codes, avatar_code, league_tier >= Moba.master_league_tier())
      |> track(:grandmaster_codes, avatar_code, league_tier >= Moba.max_league_tier())
      |> track(:invoker_codes, avatar_code, hero.total_xp_farm + hero.total_gold_farm >= Moba.max_total_farm())
      |> maybe_complete(player)

    if updates[:shard_prize], do: Moba.reward_shards!(player, updates[:shard_prize])
    Game.update_player!(player, updates)
  end

  def track_pve_progression!(hero), do: hero

  # --------------------------------------------------------

  defp find_quest_history(history, current_tier, hero) do
    Enum.find(history, fn {tier, time} ->
      parsed_time = Timex.parse!(time, "{ISO:Extended:Z}")
      parsed_tier = String.to_integer(tier)
      diff = Timex.diff(parsed_time, hero.finished_at)
      parsed_tier == current_tier && diff >= 0
    end)
  end

  defp track(progression, field, avatar_code, true) do
    updated_codes = Map.get(progression, field) ++ [avatar_code]
    Map.put(progression, field, Enum.uniq(updated_codes))
  end

  defp track(progression, _, _, false), do: progression

  defp maybe_complete(%{history: history} = progression, %{pve_tier: tier, status: current_status, user_id: user_id}) do
    next_tier = tier + 1
    quest = Map.get(@all, next_tier)
    quest_codes = Map.get(progression, quest.field)
    progression_map = Map.from_struct(progression)

    if length(quest_codes) >= quest.goal do
      history = Map.put(history, next_tier, Timex.now() |> Timex.shift(seconds: +1))
      progression = Map.put(progression_map, :history, history)
      status = if next_tier == 1 && user_id, do: "available", else: current_status
      %{pve_progression: progression, pve_tier: next_tier, status: status, shard_prize: quest.prize}
    else
      %{pve_progression: progression_map}
    end
  end
end
