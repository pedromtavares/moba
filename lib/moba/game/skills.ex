defmodule Moba.Game.Skills do
  @moduledoc """
  Manages Skill records and queries.
  See Moba.Game.Schema.Skill for more info.
  """

  alias Moba.{Repo, Game}
  alias Game.Schema.Skill
  alias Game.Query.SkillQuery

  # -------------------------------- PUBLIC API

  @doc """
  A Basic Attack is a 'virtual' Skill that all Heroes can use in a battle
  at any time. It requires no MP and has no cooldown, but only deals your Aattack
  as damage.
  """
  def basic_attack do
    %Skill{
      name: "Basic Attack",
      code: "basic_attack",
      atk_multiplier: 1,
      description: "Basic hit that deals 100% of your Attack",
      damage_type: "normal",
      mp_cost: 0,
      cooldown: 0
    }
  end

  def boss! do
    [
      get_skill_by_code!("boss_slam", false, 1),
      get_skill_by_code!("boss_bash", false, 1),
      get_skill_by_code!("boss_spell_block", false, 1)
    ]
  end

  @doc """
  Heroes need skill_levels_available to level a skill, as well as be in a certain level themselves depending on
  the skill they are trying to level. Ultimates can only be leveled at levels 10 and 20, whilst normal skills
  follow smaller intervals to not allow leveling of a single skill up to 5 immediately.
  """
  def can_level_skill?(%{skill_levels_available: levels} = hero, %{ultimate: true} = skill) when levels > 0 do
    case skill.level do
      1 -> hero.level >= 10
      2 -> hero.level >= 20
      _ -> false
    end
  end

  def can_level_skill?(%{skill_levels_available: levels} = hero, skill) when levels > 0 do
    case skill.level do
      1 -> true
      2 -> hero.level >= 6
      3 -> hero.level >= 10
      4 -> hero.level >= 14
      _ -> false
    end
  end

  def can_level_skill?(_, _), do: false

  def get_current_skills_from(skills) do
    Enum.map(skills, fn old ->
      get_skill_by_code!(old.code, true, old.level)
    end)
  end

  def get_current_skill!(code, level), do: get_skill_by_code!(code, true, level)

  def get_skill!(""), do: nil
  def get_skill!(id), do: Repo.get!(Skill, id)

  def get_skill_by_code!(code, current \\ true, level \\ 1)
  def get_skill_by_code!("", _, _), do: nil

  def get_skill_by_code!(code, current, level) do
    query = if current, do: SkillQuery.single_current(), else: SkillQuery.canon()

    Repo.get_by!(query, code: code, level: level)
  end

  @doc """
  Levels up a skill by replacing the current one (via its code) with its higher level version
  """
  def level_up_skill!(%{skills: skills} = hero, code) do
    current = Enum.find(skills, fn skill -> skill.code == code end)

    if current && can_level_skill?(hero, current) && !max_level?(current) do
      leveled = get_skill_by_code!(code, true, current.level + 1)
      replaced = skills -- [current]
      added = replaced ++ [leveled]

      Game.update_hero!(hero, %{skill_levels_available: hero.skill_levels_available - 1}, nil, added)
    else
      hero
    end
  end

  def list_all_current_skills do
    current = SkillQuery.base_current() |> Repo.all()
    current ++ [basic_attack()] ++ boss!()
  end

  def list_chosen_skills(ids) do
    SkillQuery.base_current()
    |> SkillQuery.normals()
    |> SkillQuery.get_all(ids)
    |> Repo.all()
  end

  def list_creation_skills(level, codes \\ []) do
    base_list =
      SkillQuery.base_current()
      |> SkillQuery.normals()
      |> SkillQuery.with_level(level)
      |> SkillQuery.no_level_requirement()
      |> Repo.all()

    (unlocked_list(codes, level) ++ base_list)
    |> Enum.sort_by(fn skill -> skill.mp_cost end)
  end

  def list_normal_skills do
    SkillQuery.base_canon()
    |> SkillQuery.normals()
    |> Repo.all()
  end

  def list_ultimate_skills do
    SkillQuery.base_canon()
    |> SkillQuery.ultimates()
    |> Repo.all()
  end

  def list_unlockable_skills do
    SkillQuery.canon()
    |> SkillQuery.enabled()
    |> SkillQuery.normals()
    |> SkillQuery.with_level_requirement()
    |> SkillQuery.with_level(5)
    |> Repo.all()
  end

  def max_leveled_skills(skills), do: Enum.map(skills, &get_skill_by_code!(&1.code, true, max_skill_level(&1)))

  def max_skill_level(skill) do
    cond do
      skill.ultimate -> 3
      true -> 5
    end
  end

  # --------------------------------

  defp max_level?(skill), do: skill.level >= max_skill_level(skill)

  defp unlocked_list(codes, level) when length(codes) > 0 do
    SkillQuery.base_current()
    |> SkillQuery.normals()
    |> SkillQuery.with_codes(codes)
    |> SkillQuery.with_level(level)
    |> Repo.all()
  end

  defp unlocked_list(_, _), do: []
end
