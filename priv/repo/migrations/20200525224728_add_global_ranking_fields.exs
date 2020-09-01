defmodule Moba.Repo.Migrations.AddGlobalRankingFields do
  use Ecto.Migration

  def change do
    alter table(:heroes) do
      add :global_ranking, :integer
    end

    alter table(:users) do
      add :ranking, :integer
    end
  end
end
