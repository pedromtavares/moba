defmodule Moba.Game.Schema.Preferences do
  @moduledoc """
  Used to store player-specific preferences
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :show_farm_tabs, :boolean, default: true
  end

  def changeset(model, params \\ %{}) do
    model
    |> cast(params, [
      :show_farm_tabs
    ])
  end
end
