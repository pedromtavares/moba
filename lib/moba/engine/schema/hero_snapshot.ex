defmodule Moba.Engine.Schema.HeroSnapshot do
  @moduledoc """
  Used to store the game state of a Hero when a battle finishes
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :experience, :integer
    field :level, :integer
    field :leveled_up, :boolean, default: false
    field :wins, :integer
    field :losses, :integer
    field :gold, :integer
    field :skill_levels_available, :integer
    field :league_step, :integer
    field :previous_league_step, :integer
    field :league_tier, :integer
  end

  def changeset(model, params \\ %{}) do
    model
    |> cast(params, [
      :experience,
      :level,
      :leveled_up,
      :wins,
      :losses,
      :gold,
      :skill_levels_available,
      :league_step,
      :previous_league_step,
      :league_tier
    ])
  end
end
