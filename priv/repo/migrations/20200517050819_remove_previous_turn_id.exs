defmodule Moba.Repo.Migrations.RemovePreviousTurnId do
  use Ecto.Migration

  def change do
    alter table(:turns) do
      remove :previous_turn_id
    end
  end
end
