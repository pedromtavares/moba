defmodule Moba.Game.Schema.BotOptions do
  @moduledoc """
  Used to store bot-specific options for players
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :name, :string
    field :tier, :integer
    field :codes, {:array, :string}, default: []
  end

  def changeset(model, params \\ %{}) do
    model
    |> cast(params, [
      :name,
      :tier,
      :codes
    ])
  end
end
