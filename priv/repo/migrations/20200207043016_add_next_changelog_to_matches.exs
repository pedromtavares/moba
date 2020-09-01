defmodule Moba.Repo.Migrations.AddNextChangelogToMatches do
  use Ecto.Migration

  def change do
    alter table(:matches) do
      add :next_changelog, :text
    end
  end
end
