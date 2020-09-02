defmodule Moba.Repo.Migrations.ProgressionFields do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :shard_count, :integer, default: 0
      add :medal_count, :integer, default: 0
    end
  end
end
