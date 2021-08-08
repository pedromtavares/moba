defmodule Moba.Repo.Migrations.AddUnreadMessagesCountToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :unread_messages_count, :integer, default: 0
    end
  end
end
