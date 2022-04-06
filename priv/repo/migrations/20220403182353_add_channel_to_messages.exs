defmodule Moba.Repo.Migrations.AddChannelToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      remove :code
      remove :image

      add :channel, :string
    end
  end
end
