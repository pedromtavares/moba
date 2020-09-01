defmodule Moba.Repo.Migrations.AddMobaToAvatars do
  use Ecto.Migration

  def change do
    alter table(:avatars) do
      add :moba, :string
    end
  end
end
