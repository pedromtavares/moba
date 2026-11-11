defmodule Moba.Repo.Migrations.EnforceCaseInsensitiveUsernames do
  use Ecto.Migration

  def up do
    create index(:users, ["lower(username)"], name: :users_username_lookup_index)

    # Existing accounts may share a lowercase name. Guard new claims without rewriting those accounts.
    execute """
    CREATE FUNCTION enforce_case_insensitive_username() RETURNS trigger AS $$
    BEGIN
      IF NEW.username IS NULL THEN
        RETURN NEW;
      END IF;

      IF TG_OP = 'UPDATE' AND NEW.username IS NOT DISTINCT FROM OLD.username THEN
        RETURN NEW;
      END IF;

      -- Serialize claims for the same normalized name before reading current holders.
      PERFORM pg_advisory_xact_lock(hashtext('moba.users.username'), hashtext(lower(NEW.username)));

      IF EXISTS (
        SELECT 1 FROM users
        WHERE lower(username) = lower(NEW.username) AND id IS DISTINCT FROM NEW.id
      ) THEN
        RAISE unique_violation USING
          MESSAGE = 'Username has already been taken',
          CONSTRAINT = 'users_username_case_conflict';
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql VOLATILE;
    """

    execute """
    CREATE TRIGGER users_username_case_conflict
    BEFORE INSERT OR UPDATE OF username ON users
    FOR EACH ROW EXECUTE PROCEDURE enforce_case_insensitive_username();
    """
  end

  def down do
    execute "DROP TRIGGER users_username_case_conflict ON users"
    execute "DROP FUNCTION enforce_case_insensitive_username()"
    drop index(:users, ["lower(username)"], name: :users_username_lookup_index)
  end
end
