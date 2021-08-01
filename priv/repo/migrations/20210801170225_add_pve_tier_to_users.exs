defmodule Moba.Repo.Migrations.AddPveTierToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :pve_tier, :integer, default: 0
      remove :easy_mode_count
    end
  end
end
