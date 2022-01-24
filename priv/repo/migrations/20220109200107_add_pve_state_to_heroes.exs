defmodule Moba.Repo.Migrations.AddPveStateToHeroes do
  use Ecto.Migration

  def change do
    alter table(:heroes) do
      add :pve_state, :string
      add :pve_farming_turns, :integer
      add :pve_farming_started_at, :utc_datetime
      add :pve_farming_rewards, :map
      add :pve_total_turns, :integer
      add :pve_tier, :integer
      add :total_xp_farm, :integer, default: 0
    end

    rename table(:heroes), :total_farm, to: :total_gold_farm
  end
end
