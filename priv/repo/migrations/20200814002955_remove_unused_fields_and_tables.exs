defmodule Moba.Repo.Migrations.RemoveUnusedFieldsAndTables do
  use Ecto.Migration

  def change do
    drop table("relationships")
    drop table("prizes")

    alter table("avatars") do
      remove :moba
    end

    alter table("users") do
      remove :last_ip
      remove :shared_xp_history
    end

    alter table("heroes") do
      remove :global_ranking
      remove :item_level
      remove :shared_xp_history
      remove :league_id
    end

    drop table("leagues")
  end
end
