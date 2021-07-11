defmodule Moba.Repo.Migrations.AddShardLimitToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :shard_limit, :integer, default: 100
    end
  end
end
