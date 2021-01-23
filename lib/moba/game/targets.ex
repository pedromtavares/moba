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

  def list(hero_id) do
    Repo.all(from t in Target, where: t.attacker_id == ^hero_id)
    |> Repo.preload(defender: [:avatar, :items, active_build: [skills: Game.ordered_skills_query()]])
    |> Enum.sort_by(fn target -> target.defender.level end)
  end

  @doc """
  Generates Target records by picking pre-generated bots according to their difficulty and Hero level.
  Currently 2 Targets of each difficulty is generated after every PVE battle.
  """
  def generate!(hero, unlocked_codes \\ []) do
    Repo.delete_all(from t in Target, where: t.attacker_id == ^hero.id)

    weak = create(hero, "weak", unlocked_codes)
    moderate = create(hero, "moderate", unlocked_codes, Enum.map(weak, & &1.defender.id))
    strong = create(hero, "strong", unlocked_codes, Enum.map(weak ++ moderate, & &1.defender.id))

    Map.put(hero, :targets, weak ++ moderate ++ strong)
  end

  # --------------------------------

  defp create(hero, difficulty, unlocked_codes, exclude \\ []) do
    exclude_list = [hero.id | exclude]
    level_range = level_range(hero, difficulty)

    HeroQuery.pve_targets(difficulty, level_range, exclude_list, Game.current_match().id, unlocked_codes)
    |> Repo.all()
    |> Enum.map(fn defender ->
      {:ok, target} =
        %Target{difficulty: difficulty, attacker: hero, defender: defender}
        |> Repo.insert()

      target
    end)
  end

  defp level_range(hero, difficulty) do
    case difficulty do
      "weak" ->
        minimum_or_target_level(hero.level - 3)..minimum_or_target_level(hero.level - 2)

      "moderate" ->
        minimum_or_target_level(hero.level - 1)..hero.level

      "strong" ->
        (hero.level + 1)..(hero.level + 3)
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
