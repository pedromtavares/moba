defmodule Moba.Repo.Migrations.AddTextFieldToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      modify :body, :text
    end
  end
end
