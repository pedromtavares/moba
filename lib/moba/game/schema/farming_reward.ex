defmodule Moba.Game.Schema.FarmingReward do
  @moduledoc """
  Used to store rewards from PVE farming (mining/meditating)
  """

  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field :state, :string
    field :started_at, :utc_datetime
    field :turns, :integer
    field :amount, :integer
  end

  def changeset(model, params \\ %{}) do
    model
    |> cast(params, [
      :state,
      :started_at,
      :turns,
      :amount
    ])
  end
end
