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
    |> Repo.preload(defender: HeroQuery.load())
    |> Enum.sort_by(fn target -> target.defender.total_gold_farm + target.defender.total_xp_farm end, farm_sort)
  end

  @doc """
  Generates Target records by picking pre-generated bots according to their difficulty and Hero level.
  Currently 2 Targets of each difficulty is generated after every PVE battle.
  """
  def generate!(hero, unlocked_codes \\ [])
  def generate!(%{user_id: user_id} = hero, _) when is_nil(user_id), do: hero

  def generate!(%{pve_tier: pve_tier} = hero, unlocked_codes) do
    Repo.delete_all(from t in Target, where: t.attacker_id == ^hero.id)

    {weak_count, moderate_count, strong_count} =
      cond do
        pve_tier == 0 -> {3, 3, 0}
        pve_tier == 1 -> {3, 6, 0}
        pve_tier == 2 -> {0, 6, 3}
        pve_tier == 3 -> {0, 3, 6}
        true -> {0, 0, 9}
      end

    weak = create(hero, "weak", unlocked_codes, weak_count)
    moderate = create(hero, "moderate", unlocked_codes, moderate_count, Enum.map(weak, & &1.defender.id))
    strong = create(hero, "strong", unlocked_codes, strong_count, Enum.map(weak ++ moderate, & &1.defender.id))

    Map.put(hero, :targets, weak ++ moderate ++ strong)
  end

  # --------------------------------

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
