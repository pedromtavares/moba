defmodule Moba.Repo.Migrations.AddLastChallengeAtToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :last_challenge_at, :utc_datetime
    end
  end
end
