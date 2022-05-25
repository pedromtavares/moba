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
  end
end
