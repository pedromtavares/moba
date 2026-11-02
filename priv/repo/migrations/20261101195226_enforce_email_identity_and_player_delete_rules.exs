defmodule Moba.Repo.Migrations.EnforceEmailIdentityAndPlayerDeleteRules do
  use Ecto.Migration

  @player_links [
    {:teams, :player_id, :delete_all},
    {:matches, :player_id, :delete_all},
    {:matches, :opponent_id, :delete_all},
    {:matches, :winner_id, :nilify_all},
    {:battles, :attacker_player_id, :nilify_all},
    {:battles, :defender_player_id, :nilify_all},
    {:battles, :winner_player_id, :nilify_all},
    {:battles, :initiator_player_id, :nilify_all}
  ]

  def up do
    # Never merge accounts or rewrite email-bound tokens automatically.
    execute """
    DO $$ BEGIN
      IF EXISTS (
        SELECT 1 FROM users WHERE email IS NOT NULL
        GROUP BY lower(btrim(email)) HAVING count(*) > 1
      ) THEN
        RAISE EXCEPTION 'Case-insensitive email uniqueness found conflicting accounts. Resolve lower(trim(email)) duplicates before retrying; no accounts were changed.';
      END IF;
    END $$;
    """

    create unique_index(:users, ["lower(btrim(email))"], name: :users_email_normalized_index)

    for {table_name, field, action} <- @player_links do
      drop constraint(table_name, "#{table_name}_#{field}_fkey")

      alter table(table_name) do
        modify field, references(:players, on_delete: action)
      end
    end
  end

  def down do
    for {table_name, field, _action} <- @player_links do
      drop constraint(table_name, "#{table_name}_#{field}_fkey")

      alter table(table_name) do
        modify field, references(:players, on_delete: :nothing)
      end
    end

    drop index(:users, ["lower(btrim(email))"], name: :users_email_normalized_index)
  end
end
