defmodule Moba.SiteSettings.Setting do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :integer, autogenerate: false}
  schema "site_settings" do
    field :analytics_enabled, :boolean, default: false
    field :analytics_measurement_id, :string
    field :mail_from, :string
    field :mail_from_name, :string
    timestamps()
  end

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:analytics_enabled, :analytics_measurement_id, :mail_from, :mail_from_name])
    |> update_change(:mail_from, &trim/1)
    |> update_change(:mail_from_name, &trim/1)
    |> validate_required([:mail_from_name])
    |> validate_length(:mail_from, max: 254)
    |> validate_length(:mail_from_name, max: 100)
    |> validate_format(:mail_from, ~r/\A[^\s<>@,;]+@[^\s<>@,;]+\.[^\s<>@,;]+\z/,
      message: "must be a valid email address"
    )
    |> validate_format(:mail_from_name, ~r/\A[^\r\n<>]+\z/, message: "must not contain line breaks or angle brackets")
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

  defp trim(nil), do: nil
  defp trim(value), do: String.trim(value)

  defp require_enabled_id(changeset) do
    if get_field(changeset, :analytics_enabled) do
      validate_required(changeset, [:analytics_measurement_id])
    else
      changeset
    end
  end
end
