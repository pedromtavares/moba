defmodule Moba.Repo.Migrations.RemoveStreaks do
  use Ecto.Migration

  def change do
    alter table(:heroes) do
      remove :win_streak, :integer
      remove :loss_streak, :integer
      remove :best_pve_streak, :integer

      add :buybacks, :integer, default: 0
      add :dead, :boolean, default: false
    end
  end
end
