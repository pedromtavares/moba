defmodule Moba.Repo.Migrations.AddCommunitySeenAtToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :community_seen_at, :utc_datetime
    end
  end
end
