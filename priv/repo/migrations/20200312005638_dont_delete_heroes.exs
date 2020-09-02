defmodule Moba.Repo.Migrations.DontDeleteHeroes do
  use Ecto.Migration

  def up do
    drop constraint(:heroes, "heroes_user_id_fkey")

    alter table(:heroes) do
      modify(:user_id, references(:users, on_delete: :nilify_all))
    end
  end

  def down do
    execute "ALTER TABLE heroes DROP CONSTRAINT heroes_user_id_fkey"

    alter table(:heroes) do
      modify(:user_id, references(:users, on_delete: :delete_all))
    end
  end
end
