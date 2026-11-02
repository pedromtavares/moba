defmodule Moba.Repo.Migrations.AddChatBurstCooldown do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :chat_burst_count, :integer, default: 0, null: false
      add :chat_last_message_at, :utc_datetime_usec
    end
  end
end
