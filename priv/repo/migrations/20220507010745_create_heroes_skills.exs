defmodule Moba.Repo.Migrations.CreateHeroesSkills do
  use Ecto.Migration

  alias Moba.{Repo, Game}
  alias Game.Schema.{BuildSkill, HeroSkill, Build}
  import Ecto.Query

  def up do
    drop_if_exists table(:heroes_skills)

    create table(:heroes_skills) do
      add :hero_id, references(:heroes, on_delete: :delete_all), null: false
      add :skill_id, references(:skills, on_delete: :delete_all), null: false
      timestamps()
    end

    create unique_index(:heroes_skills, [:hero_id, :skill_id])

    flush()

    from(bs in BuildSkill, join: b in assoc(bs, :build), where: b.type == "pve")
    |> Repo.all()
    |> Repo.preload(:build)
    |> create_hero_skills()

    from(b in Build, where: b.type == "pve")
    |> Repo.all()
    |> Repo.preload(:hero)
    |> update_skill_order()

    from(bs in BuildSkill,
      join: b in assoc(bs, :build),
      join: h in assoc(b, :hero),
      join: u in assoc(h, :user),
      where: u.is_bot == true,
      where: b.type == "pvp"
    )
    |> Repo.all()
    |> Repo.preload(:build)
    |> create_hero_skills()

    from(b in Build,
      join: h in assoc(b, :hero),
      join: u in assoc(h, :user),
      where: u.is_bot == true,
      where: b.type == "pvp"
    )
    |> Repo.all()
    |> Repo.preload(:hero)
    |> update_skill_order()
  end

  def create_hero_skills(build_skills) do
    Enum.map(build_skills, fn build_skill ->
      skill_id = build_skill.skill_id
      hero_id = build_skill.build.hero_id

      %HeroSkill{skill_id: skill_id, hero_id: hero_id}
      |> Repo.insert!()
    end)
  end

  def update_skill_order(builds) do
    Enum.map(builds, fn build ->
      Game.Heroes.update!(build.hero, %{
        skill_order: build.skill_order,
        item_order: build.item_order
      })
    end)
  end
end
