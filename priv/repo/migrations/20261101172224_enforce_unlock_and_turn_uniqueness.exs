defmodule Moba.Repo.Migrations.EnforceUnlockAndTurnUniqueness do
  use Ecto.Migration

  def up do
    # Preserve the first canonical entry when older races left duplicate records.
    execute "DELETE FROM unlocks newer USING unlocks older WHERE newer.user_id = older.user_id AND newer.resource_code = older.resource_code AND newer.id > older.id"

    execute "DELETE FROM turns newer USING turns older WHERE newer.battle_id = older.battle_id AND newer.number = older.number AND newer.id > older.id"

    create unique_index(:unlocks, [:user_id, :resource_code])
    create unique_index(:turns, [:battle_id, :number])
  end

  def down do
    drop unique_index(:turns, [:battle_id, :number])
    drop unique_index(:unlocks, [:user_id, :resource_code])
  end
end
