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

  def get_target!(id) do
    Repo.get!(Target, id)
    |> Repo.preload(attacker: [:items, :skills, :player], defender: [:items, :skills])
  end

  def list_targets(%{id: hero_id, pve_tier: pve_tier}) do
    farm_sort = if pve_tier >= 2, do: :desc, else: :asc

    Repo.all(from t in Target, where: t.attacker_id == ^hero_id)
    |> Repo.preload(defender: HeroQuery.load())
    |> Enum.sort_by(fn target -> target.defender.total_gold_farm + target.defender.total_xp_farm end, farm_sort)
  end

  @doc """
  Generates Target records by picking pre-generated bots according to their difficulty and Hero level.
  Currently 2 Targets of each difficulty is generated after every PVE battle.
  """
  def generate!(hero, unlocked_codes \\ [])
  def generate!(%{player_id: player_id} = hero, _) when is_nil(player_id), do: hero

  def generate!(%{pve_tier: pve_tier} = hero, unlocked_codes) do
    Repo.delete_all(from t in Target, where: t.attacker_id == ^hero.id)

    {weak_count, moderate_count, strong_count} = difficulty_counts(pve_tier)

    weak = create(hero, "weak", unlocked_codes, weak_count)
    moderate = create(hero, "moderate", unlocked_codes, moderate_count, Enum.map(weak, & &1.defender.id))
    strong = create(hero, "strong", unlocked_codes, strong_count, Enum.map(weak ++ moderate, & &1.defender.id))

    Map.put(hero, :targets, weak ++ moderate ++ strong)
  end

  # --------------------------------

  def difficulty_counts(0), do: {3, 3, 0}
  def difficulty_counts(1), do: {3, 6, 0}
  def difficulty_counts(2), do: {0, 6, 3}
  def difficulty_counts(3), do: {0, 3, 6}
  def difficulty_counts(_), do: {0, 0, 9}

  def candidates(hero, difficulty, unlocked_codes, limit, exclude \\ []) do
    farm = div(hero.total_xp_farm + hero.total_gold_farm, 2)

    HeroQuery.pve_targets(difficulty, farm_range(farm, difficulty), exclude, unlocked_codes, limit)
    |> HeroQuery.load()
    |> Repo.all()
  end

  defp create(hero, difficulty, unlocked_codes, limit, exclude \\ []) do
    exclude_list = [hero.id | exclude]
    total_xp_farm = div(hero.total_xp_farm + hero.total_gold_farm, 2)
    farm_range = farm_range(total_xp_farm, difficulty)

    HeroQuery.pve_targets(difficulty, farm_range, exclude_list, unlocked_codes, limit)
    |> Repo.all()
    |> Enum.map(fn defender ->
      {:ok, target} =
        %Target{difficulty: difficulty, attacker: hero, defender: defender}
        |> Repo.insert()

      target
    end)
  end

  defp farm_range(total_xp, difficulty) when total_xp < 7000 do
    base_xp = 600

    case difficulty do
      "weak" ->
        minimum_farm(total_xp - base_xp * 4)..minimum_farm(total_xp - base_xp * 2)

      "moderate" ->
        minimum_farm(total_xp - base_xp * 3)..total_xp

      "strong" ->
        total_xp..(total_xp + base_xp * 3)
    end
  end

  defp farm_range(total_xp, difficulty) when total_xp < 20000 do
    base_xp = 1200

    case difficulty do
      "weak" ->
        (total_xp - base_xp * 3)..(total_xp - base_xp * 1)

      "moderate" ->
        (total_xp - base_xp * 1)..(total_xp + base_xp * 2)

      "strong" ->
        total_xp..(total_xp + base_xp * 4)
    end
  end

  defp farm_range(total_xp, difficulty) do
    base_xp = 2000

    case difficulty do
      "weak" ->
        (total_xp - base_xp * 2)..(total_xp + base_xp * 1)

      "moderate" ->
        total_xp..(total_xp + base_xp * 3)

      "strong" ->
        total_xp..(total_xp + base_xp * 6)
    end
  end

  defp minimum_farm(farm) when farm < 0, do: 0
  defp minimum_farm(farm), do: farm
end
