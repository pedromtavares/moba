defmodule Moba.Repo.Migrations.AddBackgroundToAvatars do
  use Ecto.Migration

  def change do
    alter table(:avatars) do
      add :background, :string
    end
  end
end
