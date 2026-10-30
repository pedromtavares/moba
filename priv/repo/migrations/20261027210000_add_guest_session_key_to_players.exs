defmodule Moba.Repo.Migrations.AddGuestSessionKeyToPlayers do
  use Ecto.Migration

  def change do
    alter table(:players) do
      add :guest_session_key, :string
    end

    create unique_index(:players, [:guest_session_key])
  end
end
