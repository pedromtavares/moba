defmodule Moba.Repo.Migrations.AddPveRankingToHeroes do
  use Ecto.Migration

  def change do
    alter table(:heroes) do
      add :pve_ranking, :integer
    end
  end
end
