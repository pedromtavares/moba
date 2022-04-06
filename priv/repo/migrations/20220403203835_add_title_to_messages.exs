defmodule Moba.Repo.Migrations.AddTitleToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :title, :string
    end
  end
end
