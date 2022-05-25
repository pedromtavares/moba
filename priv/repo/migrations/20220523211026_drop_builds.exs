defmodule Moba.Repo.Migrations.DropBuilds do
  use Ecto.Migration

  def up do
    alter table(:heroes) do
      remove :active_build_id
    end

    drop table(:builds_skills)
    drop table(:builds)
  end
end
