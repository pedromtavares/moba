defmodule Moba.Repo.Migrations.AddDescriptionToAvatars do
  use Ecto.Migration

  def change do
    alter table(:avatars) do
      add :description, :text
    end
  end
end
