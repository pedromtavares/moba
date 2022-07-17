defmodule Moba.Game.Schema.PveProgression do
  @moduledoc """
  Used to store progression related to PVE/Training
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :season_codes, {:array, :string}, default: []
    field :master_codes, {:array, :string}, default: []
    field :grandmaster_codes, {:array, :string}, default: []
    field :invoker_codes, {:array, :string}, default: []
    field :history, :map, default: %{}
  end

  def changeset(model, params \\ %{}) do
    model
    |> cast(params, [
      :season_codes,
      :master_codes,
      :grandmaster_codes,
      :invoker_codes,
      :history
    ])
  end
end
