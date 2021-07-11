defmodule Moba.Repo.Migrations.CreateSkins do
  use Ecto.Migration

  def change do
    create table(:skins) do
      add :background, :string
      add :code, :string
      add :name, :string
      add :author_name, :string
      add :author_link, :string
      add :avatar_code, :string
      add :league_tier, :integer
      timestamps()
    end

    alter table(:heroes) do
      add :skin_id, references(:skins, on_delete: :nilify_all)
    end
  end
end
