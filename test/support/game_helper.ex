defmodule Test.GameHelper do
  alias Moba.Game
  import Test.AccountsHelper

  def create_base_hero(attrs \\ %{}, user \\ create_user(), avatar \\ base_avatar()) do
    base = %{name: "Test"}

    Moba.create_current_pve_hero!(
      Map.merge(base, attrs),
      user,
      avatar,
      base_skills()
    )
  end

  def build_base_hero(attrs \\ %{}), do: Map.merge(%Game.Schema.Hero{}, attrs)

  def create_bot_hero(level \\ 1, difficulty \\ "strong") do
    Game.create_bot_hero!(
      base_avatar(),
      level,
      difficulty,
      nil,
      create_user()
    )
  end

  def base_build(type \\ "pve", hero \\ create_base_hero(), skills \\ base_skills()) do
    Game.Builds.create!(type, hero, skills)
  end

  def base_avatar, do: Game.get_avatar_by_code!("phantom_assassin")

  def weak_avatar do
    Game.create_avatar!(
      %Game.Schema.Avatar{ultimate_code: "coup"},
      %{
        atk: 1,
        total_hp: 10,
        total_mp: 10,
        atk_per_level: 1,
        hp_per_level: 1,
        mp_per_level: 1,
        speed: 200,
        armor: 0,
        power: 0
      }
    )
  end

  def strong_avatar do
    Game.create_avatar!(
      %Game.Schema.Avatar{ultimate_code: "coup", role: "carry", enabled: true, current: true},
      %{
        atk: 1000,
        total_hp: 10000,
        total_mp: 30,
        atk_per_level: 1,
        hp_per_level: 5,
        mp_per_level: 1,
        speed: 200,
        armor: 1000,
        power: 1000
      }
    )
  end

  def alternate_avatar, do: Game.get_avatar_by_code!("juggernaut")

  def base_ultimate, do: Game.get_skill_by_code!("coup", false, 1)

  def base_skill, do: Game.get_skill_by_code!("decay", false, 1)

  def base_skills do
    Enum.map(
      ["decay", "shuriken_toss", "fiery_soul"],
      &Game.get_skill_by_code!(&1, false, 1)
    )
  end

  def alternate_skills do
    Enum.map(
      ["double_edge", "empower", "feast"],
      &Game.get_skill_by_code!(&1, false, 1)
    )
  end

  def base_item, do: Game.get_item_by_code!("boots_of_speed")

  def alternate_item, do: Game.get_item_by_code!("silver_edge")

  def base_normal_items do
    Enum.map(
      ["boots_of_speed", "sages_mask", "chainmail"],
      &Game.get_item_by_code!(&1)
    )
  end

  def base_rare_item, do: Game.get_item_by_code!("tranquil_boots")
end
