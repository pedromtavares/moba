defmodule Moba.Repo.Migrations.AddShardsRewardToHeroes do
  use Ecto.Migration

  def change do
    alter table(:heroes) do
      add :shards_reward, :integer, default: 0
    end
  end
end
