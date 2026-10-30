defmodule Moba.SiteSettings.Setting do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :integer, autogenerate: false}
  schema "site_settings" do
    field :analytics_enabled, :boolean, default: false
    field :analytics_measurement_id, :string
    timestamps()
  end

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:analytics_enabled, :analytics_measurement_id])
    |> update_change(:analytics_measurement_id, fn
      nil -> nil
      id -> id |> String.trim() |> String.upcase()
    end)
    |> validate_format(:analytics_measurement_id, ~r/\AG-[A-Z0-9]+\z/,
      message: "must be a GA4 measurement ID beginning with G-"
    )
    |> validate_length(:analytics_measurement_id, max: 32)
    |> require_enabled_id()
  end

  defp require_enabled_id(changeset) do
    if get_field(changeset, :analytics_enabled) do
      validate_required(changeset, [:analytics_measurement_id])
    else
      changeset
    end
  end
end
