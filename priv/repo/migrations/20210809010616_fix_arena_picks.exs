defmodule Moba.Repo.Migrations.FixArenaPicks do
  use Ecto.Migration

  def change do
    alter table(:arena_picks) do
      modify :hero_id, references(:heroes, on_delete: :delete_all),
        from: references(:heroes, on_delete: :nothing)
    end
  end
end
