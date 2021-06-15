defmodule Moba.Repo.Migrations.AddEasyModeCountToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :easy_mode_count, :integer, default: 0
    end

    alter table(:heroes) do
      add :easy_mode, :boolean, default: false
    end
  end
end
