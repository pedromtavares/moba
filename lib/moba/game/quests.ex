defmodule Moba.Game.Quests do
  @moduledoc """
  Manages Quest records and queries.
  See Moba.Game.Schema.Quest for more info.

  """

  alias Moba.{Repo, Game, Accounts}
  alias Game.Schema.{Quest, QuestProgression}
  import Ecto.Query

  def get_by_code_and_level!(code, level), do: Repo.get_by!(Quest, code: code, level: level)

  def get_all_by_code(code), do: Repo.all(from q in Quest, where: q.code == ^code, order_by: [asc: :level])

  def current_progression_for(code, user_id) do
    code
    |> get_all_by_code()
    |> find_progressions(user_id)
    |> Enum.find(&is_nil(&1.completed_at))
  end

  def last_completed_for(%{user_id: user_id, finished_at: hero_finished_at}) do
    Repo.all(from p in load_progression(), where: p.user_id == ^user_id, where: p.completed_at >= ^hero_finished_at)
    |> List.first()
  end

  def list_title_for(user_id) do
    Repo.all(from p in load_progression(), where: p.user_id == ^user_id, where: not is_nil(p.completed_at))
  end

  def find_progression_by!(user_id, quest_id) do
    Repo.insert(%QuestProgression{user_id: user_id, quest_id: quest_id}, on_conflict: :nothing)
    Repo.get_by!(QuestProgression, user_id: user_id, quest_id: quest_id) |> Repo.preload([:user, :quest])
  end

  def list_progressions(user_id) do
    Repo.all(from p in QuestProgression, where: p.user_id == ^user_id) |> Repo.preload([:user, :quest])
  end

  def track(code, %{user_id: user_id} = opts) do
    get_all_by_code(code)
    |> find_progressions(user_id)
    |> Enum.map(&track_progression(code, &1, opts))
  end

  defp apply_rewards(%{quest: quest, user: user} = progression) do
    base_rewards = %{shard_count: user.shard_count + quest.shard_prize}

    rewards =
      if quest.code == "season" do
        Map.put(base_rewards, :pve_tier, quest.level)
      else
        base_rewards
      end

    Accounts.update_user!(user, rewards)

    progression
  end

  defp complete!(progression, final_value) do
    update!(progression, %{completed_at: Timex.now(), current_value: final_value})
  end

  defp find_progressions(quests, user_id), do: Enum.map(quests, &find_progression_by!(user_id, &1.id))

  defp track_progression(_, %{completed_at: completed_at} = progression, _) when not is_nil(completed_at),
    do: progression

  defp track_progression("season", %{user_id: user_id, quest: %{final_value: final_value}} = progression, _) do
    user = Accounts.get_user!(user_id)
    master_collection = Enum.filter(user.hero_collection, fn hero -> hero["tier"] >= 5 end)
    update_or_complete!(progression, length(master_collection), final_value)
  end

  defp load_progression(queryable \\ QuestProgression), do: preload(queryable, [:quest])

  defp update_or_complete!(progression, current_value, final_value) do
    if current_value >= final_value do
      progression
      |> complete!(final_value)
      |> apply_rewards()
    else
      update!(progression, %{current_value: current_value})
    end
  end

  defp update!(progression, attrs) do
    QuestProgression.changeset(progression, attrs)
    |> Repo.update!()
  end
end
