defmodule Moba.Repo.Migrations.ChangeDescriptionToText do
  use Ecto.Migration

  def change do
    alter table(:skills) do
      modify :description, :text
    end

    alter table(:items) do
      modify :description, :text
    end
  end
end
