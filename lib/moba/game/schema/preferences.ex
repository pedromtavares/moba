defmodule Moba.Game.Schema.Preferences do
  @moduledoc """
  Used to store player-specific preferences
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :show_farm_tabs, :boolean, default: true
    field :auto_matchmaking, :boolean, default: true
    field :battle_speed, Ecto.Enum, values: [:normal, :fast, :instant], default: :normal
  end

  def changeset(model, params \\ %{}) do
    model
    |> cast(params, [
      :show_farm_tabs,
      :auto_matchmaking,
      :battle_speed
    ])
  end
end
