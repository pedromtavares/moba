defmodule Moba.Game.Skills do
  @moduledoc """
  Manages Skill records and queries.
  See Moba.Game.Schema.Skill for more info.
  """

  alias Moba.{Repo, Game}
  alias Game.Schema.Skill
  alias Game.Query.SkillQuery

  @max_level Moba.max_hero_level()

  # -------------------------------- PUBLIC API

  @doc """
  A Basic Attack is a 'virtual' Skill that all Heroes can use in a battle
  at any time. It requires no MP and has no cooldown, but only deals your ATK
  as damage.
  """
  def basic_attack do
    %Skill{
      name: "Basic Attack",
      code: "basic_attack",
      atk_multiplier: 1,
      description: "Hit with a Basic Attack for 100% ATK",
      mp_cost: 0,
      cooldown: 0
    }
  end

  def get!(""), do: nil
  def get!(id), do: Repo.get!(Skill, id)

  def get_by_code!(code, current \\ true, level \\ 1)
  def get_by_code!("", _, _), do: nil

  def get_by_code!(code, current, level) do
    current_match = current && Game.current_match()
    match_id = (current_match && current_match.id) || nil

    get_by_match(match_id, code, level)
  end

  @doc """
  Levels up a skill by replacing the current one (via its code) with its higher level version
  """
  def level_up!(%{active_build: %{skills: skills} = build} = hero, code) do
    current = Enum.find(skills, fn skill -> skill.code == code end)

    if current && can_level?(hero, current) && !max_level?(current) do
      leveled = get_by_code!(code, true, current.level + 1)
      replaced = skills -- [current]

      build = Game.replace_build_skills!(build, replaced ++ [leveled])

      hero
      |> Game.update_hero!(%{skill_levels_available: hero.skill_levels_available - 1})
      |> Map.put(:active_build, build)
    else
      hero
    end
  end

  @doc """
  Heroes need skill_levels_available to level a skill, as well as be in a certain level themselves depending on
  the skill they are trying to level. Ultimates can only be leveled at levels 10 and 20, whilst normal skills
  follow smaller intervals to not allow leveling of a single skill up to 5 immediately.
  """
  def can_level?(%{skill_levels_available: levels} = hero, %{ultimate: true} = skill) when levels > 0 do
    case skill.level do
      1 -> hero.level >= 10
      2 -> hero.level >= 20
      _ -> false
    end
  end

  def can_level?(%{skill_levels_available: levels} = hero, skill) when levels > 0 do
    case skill.level do
      1 -> true
      2 -> hero.level >= 6
      3 -> hero.level >= 10
      4 -> hero.level >= 14
      _ -> false
    end
  end

  def can_level?(_, _), do: false

  def max_level(skill) do
    cond do
      skill.ultimate -> 3
      true -> 5
    end
  end

  def levels_available_for(hero_level) when hero_level == @max_level, do: 14
  def levels_available_for(hero_level), do: div(hero_level, 2)

  def get_current_from(skills) do
    Enum.map(skills, fn old ->
      get_by_code!(old.code, true, old.level)
    end)
  end

  def list_normals do
    SkillQuery.base_canon()
    |> SkillQuery.normals()
    |> Repo.all()
  end

  def list_ultimates do
    SkillQuery.base_canon()
    |> SkillQuery.ultimates()
    |> Repo.all()
  end

  def list_creation(level, codes \\ []) do
    base_list =
      SkillQuery.base_current()
      |> SkillQuery.normals()
      |> SkillQuery.with_level(level)
      |> SkillQuery.no_level_requirement()
      |> Repo.all()

    (unlocked_list(codes, level) ++ base_list)
    |> Enum.sort_by(fn skill -> skill.mp_cost end)
  end

  def list_chosen(ids) do
    SkillQuery.base_current()
    |> SkillQuery.normals()
    |> SkillQuery.get_all(ids)
    |> Repo.all()
  end

  def list_unlockable do
    SkillQuery.canon()
    |> SkillQuery.enabled()
    |> SkillQuery.normals()
    |> SkillQuery.with_level_requirement()
    |> SkillQuery.with_level(5)
    |> Repo.all()
  end

  def ordered_query, do: SkillQuery.ordered()

  # --------------------------------

  defp get_by_match(nil, code, level) do
    Repo.get_by!(SkillQuery.canon(Skill), code: code, level: level)
  end

  defp get_by_match(match_id, code, level) do
    Repo.get_by!(Skill, code: code, match_id: match_id, level: level)
  end

  defp max_level?(skill), do: skill.level >= max_level(skill)

  defp unlocked_list(codes, level) when length(codes) > 0 do
    SkillQuery.base_current()
    |> SkillQuery.normals()
    |> SkillQuery.with_codes(codes)
    |> SkillQuery.with_level(level)
    |> Repo.all()
  end

  defp unlocked_list(_, _), do: []
end
