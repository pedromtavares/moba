defmodule Moba.Repo.Migrations.CreatePrizes do
  use Ecto.Migration

  def change do
    create table(:prizes) do
      add :tier, :integer
      add :pending, :boolean, default: true
      add :avatar_code, :string

      add :user_id, references(:users, on_delete: :delete_all)

      timestamps()
    end

    alter table(:avatars) do
      add :prize_tier, :integer
    end
  end
end
