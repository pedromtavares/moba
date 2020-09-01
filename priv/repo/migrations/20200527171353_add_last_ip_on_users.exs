defmodule Moba.Repo.Migrations.AddLastIpOnUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :last_ip, :string
    end
  end
end
