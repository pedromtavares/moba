defmodule Moba.Repo.Migrations.AddEmailSenderToSiteSettings do
  use Ecto.Migration

  def change do
    alter table(:site_settings) do
      add :mail_from, :string
      add :mail_from_name, :string, default: "Browser MOBA", null: false
    end
  end
end
