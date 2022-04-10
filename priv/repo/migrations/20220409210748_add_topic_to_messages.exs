defmodule Moba.Repo.Migrations.AddTopicToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :topic, :string
    end

    create index(:messages, [:channel])
  end
end
