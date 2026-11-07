defmodule Moba.Game.Quests do
  @moduledoc """
  Manages tracking of player PVE progression
  """

  alias Moba.{Game, Repo}
  import Ecto.Query
  alias Game.Schema.PveProgression

  @platinum_league_tier Moba.platinum_league_tier()

  @all %{
    1 => %{
      title: "Novice",
      description: "Finish a training on Platinum League or higher",
      training_bonus: "+1000 starting gold (1000 -> 2000)",
      difficulty: "3 Easy targets + 6 Medium targets",
      max_league: "Master League",
      prize: 200,
      goal: 1,
      field: :season_codes
    },
    2 => %{
      title: "Adept",
      description: "Finish a training on Master League or higher",
      difficulty: "6 Medium targets + 3 Hard targets",
      prize: 300,
      goal: 1,
      field: :master_codes
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
      description: "Finish training with 20 different Avatars on the Master League or above",
      training_bonus: "Ability to refresh Targets up to 10 times",
      prize: 1000,
      goal: 20,
      field: :master_codes
    },
    6 => %{
      title: "Grandmaster",
      description: "Finish training with 20 different Avatars on the Grandmaster League",
      training_bonus: "Ability to refresh Targets up to 15 times",
      prize: 2500,
      goal: 20,
      field: :grandmaster_codes
    },
    7 => %{
      title: "Invoker",
      description:
        "Complete perfect Grandmaster runs with 20 different Avatars: 60K solo farm or 60K average team farm",
      difficulty: "9 Hard targets",
      max_league: "Grandmaster League",
      prize: 5000,
      goal: 20,
      field: :invoker_codes
    }
  }

  def get_quest(tier) when tier > 7, do: @all[7]
  def get_quest(tier), do: @all[tier]

  def last_completed_quest(%{player: %{pve_progression: %{history: history}, pve_tier: current_tier}} = hero) do
    with {tier, _} <- find_quest_history(history, current_tier, hero) do
      get_quest(String.to_integer(tier))
    else
      _ -> nil
    end
  end

  def track_pve_progression!(%{training_team_id: id} = hero) when not is_nil(id) do
    case Repo.get(Game.Schema.TrainingTeam, id) do
      %{phase: "finished", finished_at: finished} = team when not is_nil(finished) ->
        track_team_pve_progression!(team)

      _ ->
        hero
    end
  end

  def track_pve_progression!(%{player: player, league_tier: league_tier, avatar: %{code: avatar_code}} = hero)
      when league_tier >= @platinum_league_tier do
    perfect = hero.total_xp_farm + hero.total_gold_farm >= Moba.max_total_farm()
    track_run_progression!(player.id, [avatar_code], league_tier, perfect)
  end

  def track_pve_progression!(hero), do: hero

  def track_team_pve_progression!(
        %{phase: "finished", finished_at: finished, league_tier: league, hero_ids: ids, total_farm: farm} = team
      )
      when not is_nil(finished) and league >= @platinum_league_tier and length(ids) == 3 and is_integer(farm) do
    codes =
      from(h in Game.Schema.Hero,
        join: a in assoc(h, :avatar),
        where: h.training_team_id == ^team.id and h.player_id == ^team.player_id and h.id in ^ids,
        select: a.code
      )
      |> Repo.all()

    perfect = farm >= Moba.max_total_farm() * length(ids)
    track_run_progression!(team.player_id, codes, league, perfect)
  end

  def track_team_pve_progression!(team), do: team

  defp track_run_progression!(player_id, avatar_codes, league_tier, perfect) do
    {:ok, updated} =
      Repo.transaction(fn ->
        stored = Repo.get!(Game.Schema.Player, player_id)

        if stored.user_id do
          Repo.one!(from u in Moba.Accounts.Schema.User, where: u.id == ^stored.user_id, lock: "FOR UPDATE")
        end

        player =
          Repo.one!(from p in Game.Schema.Player, where: p.id == ^player_id, lock: "FOR UPDATE") |> Repo.preload(:user)

        progression = player.pve_progression || %PveProgression{}

        updates =
          progression
          |> track(:season_codes, avatar_codes, true)
          |> track(:master_codes, avatar_codes, league_tier >= Moba.master_league_tier())
          |> track(:grandmaster_codes, avatar_codes, league_tier >= Moba.max_league_tier())
          |> track(
            :invoker_codes,
            avatar_codes,
            league_tier >= Moba.max_league_tier() && perfect
          )
          |> maybe_complete(player)

        if updates[:shard_prize], do: Moba.reward_shards!(player, updates[:shard_prize])
        Game.update_player!(player, updates)
      end)

    updated
  end

  # --------------------------------------------------------

  defp find_quest_history(history, current_tier, hero) do
    Enum.find(history, fn {tier, time} ->
      parsed_time = Timex.parse!(time, "{ISO:Extended:Z}")
      parsed_tier = String.to_integer(tier)
      diff = Timex.diff(parsed_time, hero.finished_at)
      parsed_tier == current_tier && diff >= 0
    end)
  end

  defp track(progression, field, avatar_codes, true) do
    updated_codes = Map.get(progression, field) ++ avatar_codes
    Map.put(progression, field, Enum.uniq(updated_codes))
  end

  defp track(progression, _, _, false), do: progression

  defp maybe_complete(
         %{history: history} = progression,
         %{pve_tier: tier, status: current_status, user_id: user_id} = player
       ) do
    next_tier = tier + 1
    quest = Map.get(@all, next_tier)
    progression_map = Map.from_struct(progression)

    if quest do
      quest_codes = Map.get(progression, quest.field)

      if length(quest_codes) >= quest.goal do
        history = Map.put(history, next_tier, Timex.now() |> Timex.shift(seconds: +1))
        progression = %{progression | history: history}
        status = if next_tier == 1 && user_id, do: "available", else: current_status

        progression
        |> maybe_complete(%{player | pve_tier: next_tier, status: status})
        |> Map.put_new(:pve_tier, next_tier)
        |> Map.put_new(:status, status)
        |> Map.update(:shard_prize, quest.prize, &(&1 + quest.prize))
      else
        %{pve_progression: progression_map}
      end
    else
      %{pve_progression: progression_map}
    end
  end
end
