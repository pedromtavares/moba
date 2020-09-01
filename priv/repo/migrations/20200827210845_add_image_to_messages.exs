defmodule Moba.Repo.Migrations.AddImageToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :image, :string
    end
    rename table("messages"), :avatar_code, to: :code
  end
end
