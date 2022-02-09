defmodule Moba.Game.Quests do
  @moduledoc """
  Manages Quest records and queries.
  See Moba.Game.Schema.Quest for more info.

  """

  alias Moba.{Repo, Game, Accounts}
  alias Game.Schema.{Quest, QuestProgression}
  import Ecto.Query

  @platinum_league_tier Moba.platinum_league_tier()

  def find_progression_by!(user_id, quest_id) do
    Repo.insert(%QuestProgression{user_id: user_id, quest_id: quest_id}, on_conflict: :nothing)
    Repo.get_by!(QuestProgression, user_id: user_id, quest_id: quest_id) |> Repo.preload([:user, :quest])
  end

  def generate_daily_progressions!(nil) do
    query =
      from qp in QuestProgression,
        join: q in assoc(qp, :quest),
        where: not is_nil(qp.completed_at),
        where: q.daily == true

    user_ids = Repo.all(query) |> Enum.map(& &1.user_id)
    Repo.delete_all(query)

    Enum.map(user_ids, &generate_daily_progressions!(&1))
  end

  def generate_daily_progressions!(user_id) do
    quests = Repo.all(from q in Quest, where: q.daily == true)
    find_progressions(quests, user_id)
  end

  def get_all_by_code(code), do: Repo.all(from q in Quest, where: q.code == ^code, order_by: [asc: :level])

  def get_by_code_and_level!(code, level), do: Repo.get_by!(Quest, code: code, level: level)

  def last_completed_progressions(%{finished_at: nil}), do: nil

  def last_completed_progressions(%{user_id: user_id, finished_at: hero_finished_at}) do
    Repo.all(from p in progressions_by_user(user_id), where: p.completed_at >= ^hero_finished_at)
  end

  def list_title_progressions(user_id) do
    Repo.all(
      from p in progressions_by_user(user_id),
        join: q in assoc(p, :quest),
        where: q.daily == false,
        where: not is_nil(p.completed_at)
    )
  end

  def list_progressions(user_id, daily) do
    Repo.all(from p in progressions_by_user(user_id), join: q in assoc(p, :quest), where: q.daily == ^daily)
  end

  def list_progressions_by_code(user_id, nil), do: progressions_by_user(user_id)

  def list_progressions_by_code(user_id, quest_code) do
    quest_code
    |> get_all_by_code()
    |> find_progressions(user_id)
  end

  def list_season_progressions(user_id) do
    Moba.season_quest_codes()
    |> Enum.map(&get_all_by_code(&1))
    |> List.flatten()
    |> find_progressions(user_id)
  end

  def track_pve(%{user_id: user_id, league_tier: league_tier} = hero)
      when league_tier >= @platinum_league_tier do
    track("season", user_id, hero)

    if league_tier >= Moba.master_league_tier() do
      track("daily_master", user_id, hero)
      track("season_master", user_id, hero)
    end

    if league_tier >= Moba.max_league_tier() do
      track("daily_grandmaster", user_id, hero)
      track("season_grandmaster", user_id, hero)

      if hero.total_xp_farm + hero.total_gold_farm >= Moba.maximum_total_farm() do
        track("daily_perfect", user_id, hero)
        track("season_perfect", user_id, hero)
      end
    end

    hero
  end

  def track_pve(hero), do: hero

  defp apply_rewards(%{quest: quest, user: user} = progression) do
    base_rewards = %{shard_count: user.shard_count + quest.shard_prize}

    rewards =
      if String.contains?(quest.code, "season"), do: season_rewards(user, quest, base_rewards), else: base_rewards

    Accounts.update_user!(user, rewards)

    progression
  end

  defp find_progressions(quests, user_id), do: Enum.map(quests, &find_progression_by!(user_id, &1.id))

  defp load_progression(queryable \\ QuestProgression), do: preload(queryable, [:quest])

  defp progressions_by_user(user_id) do
    from p in load_progression(), where: p.user_id == ^user_id
  end

  defp season_rewards(_, %{level: quest_level}, base_rewards) do
    rewards = Map.put(base_rewards, :pve_tier, quest_level)

    if quest_level >= 1 do
      Map.put(rewards, :status, "available")
    else
      rewards
    end
  end

  defp track(code, user_id, hero) do
    get_all_by_code(code)
    |> find_progressions(user_id)
    |> Enum.map(&track_progression(code, &1, hero))
  end

  defp track_progression(_, %{completed_at: completed_at} = progression, _) when not is_nil(completed_at) do
    progression
  end

  defp track_progression(_, %{quest: %{final_value: final_value}} = progression, %{avatar: %{code: avatar_code}}) do
    update_or_complete!(progression, avatar_code, final_value)
  end

  defp update_or_complete!(%{history_codes: current_codes} = progression, avatar_code, final_value) do
    new_codes = Enum.uniq(current_codes ++ [avatar_code])
    current_value = length(new_codes)

    if current_value >= final_value do
      progression
      |> update_completed!(final_value, new_codes)
      |> apply_rewards()
    else
      update!(progression, %{current_value: current_value, history_codes: new_codes})
    end
  end

  defp update_completed!(progression, final_value, history_codes) do
    update!(progression, %{completed_at: Timex.now(), current_value: final_value, history_codes: history_codes})
  end

  defp update!(progression, attrs) do
    QuestProgression.changeset(progression, attrs)
    |> Repo.update!()
  end
end
