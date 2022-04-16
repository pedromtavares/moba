defmodule Moba.Repo.Migrations.RemovePowEmailConfirmation do
  use Ecto.Migration

  def change do
    alter table(:users) do
      remove :email_confirmation_token, :string
      remove :email_confirmed_at, :utc_datetime
      remove :unconfirmed_email, :string
    end
  end
end
