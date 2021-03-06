defmodule Moba.Game.Targets do
  @moduledoc """
  Manages Target records and queries.
  See Moba.Game.Schema.Target for more info.
  """

  alias Moba.{Repo, Game}
  alias Game.Schema.Target
  alias Game.Query.HeroQuery
  import Ecto.Query, only: [from: 2]

  # -------------------------------- PUBLIC API

  def get!(id) do
    Repo.get!(Target, id)
    |> Repo.preload(attacker: [:items, active_build: [:skills]], defender: [:items, active_build: [:skills]])
  end

  def list(hero_id, farm_sort \\ :asc) do
    Repo.all(from t in Target, where: t.attacker_id == ^hero_id)
    |> Repo.preload(defender: [:avatar, :items, active_build: [skills: Game.ordered_skills_query()]])
    |> Enum.sort_by(fn target -> target.defender.total_farm end, farm_sort)
  end

  @doc """
  Generates Target records by picking pre-generated bots according to their difficulty and Hero level.
  Currently 2 Targets of each difficulty is generated after every PVE battle.
  """
  def generate!(hero, unlocked_codes \\ []) do
    Repo.delete_all(from t in Target, where: t.attacker_id == ^hero.id)
    limit = if Game.veteran_hero?(hero), do: 3, else: 2

    weak = create(hero, "weak", unlocked_codes, limit)
    moderate = create(hero, "moderate", unlocked_codes, limit, Enum.map(weak, & &1.defender.id))
    strong = create(hero, "strong", unlocked_codes, limit, Enum.map(weak ++ moderate, & &1.defender.id))

    Map.put(hero, :targets, weak ++ moderate ++ strong)
  end

  # --------------------------------

  defp create(hero, difficulty, unlocked_codes, limit, exclude \\ []) do
    exclude_list = [hero.id | exclude]
    level_range = level_range(hero, difficulty)
    current_match = Game.current_match()

    # Grab heroes from previous match when mid-restart
    match_id =
      if current_match.last_server_update_at do
        current_match.id
      else
        current_match.id - 1
      end

    HeroQuery.pve_targets(difficulty, level_range, exclude_list, match_id, unlocked_codes, limit)
    |> Repo.all()
    |> Enum.map(fn defender ->
      {:ok, target} =
        %Target{difficulty: difficulty, attacker: hero, defender: defender}
        |> Repo.insert()

      target
    end)
  end

  defp level_range(%{level: level}, difficulty) when level < 10 do
    case difficulty do
      "weak" ->
        minimum_or_target_level(level - 3)..minimum_or_target_level(level - 2)

      "moderate" ->
        minimum_or_target_level(level - 1)..level

      "strong" ->
        level..(level + 2)
    end
  end

  defp level_range(%{level: level}, difficulty) when level < 25 do
    case difficulty do
      "weak" ->
        (level - 2)..(level - 1)

      "moderate" ->
        level..(level + 1)

      "strong" ->
        (level + 1)..(level + 3)
    end
  end

  defp level_range(%{level: level}, difficulty) do
    case difficulty do
      "weak" ->
        level..(level + 1)

      "moderate" ->
        (level + 1)..(level + 3)

      "strong" ->
        (level + 3)..(level + 6)
    end
  end

  defp minimum_or_target_level(level) do
    case level do
      n when n in [-2, -1] -> 0
      0 -> 1
      _ -> level
    end
  end
end
