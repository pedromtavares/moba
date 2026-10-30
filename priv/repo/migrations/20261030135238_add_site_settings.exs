defmodule Moba.Repo.Migrations.AddSiteSettings do
  use Ecto.Migration

  def change do
    create table(:site_settings, primary_key: false) do
      add :id, :integer, primary_key: true
      add :analytics_enabled, :boolean, default: false, null: false
      add :analytics_measurement_id, :string
      timestamps()
    end

    create constraint(:site_settings, :single_site_settings, check: "id = 1")

    execute(
      "INSERT INTO site_settings (id, analytics_enabled, inserted_at, updated_at) VALUES (1, false, NOW(), NOW())",
      "DELETE FROM site_settings WHERE id = 1"
    )
  end
end
