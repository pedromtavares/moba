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
    field :win_streak, :integer
    field :loss_streak, :integer
    field :wins, :integer
    field :losses, :integer
    field :ties, :integer
    field :gold, :integer
    field :skill_levels_available, :integer
    field :pvp_points, :integer
    field :pve_points, :integer
    field :league_step, :integer
    field :previous_league_step, :integer
    field :league_tier, :integer
    field :pvp_wins, :integer
    field :pvp_losses, :integer
    field :pvp_ranking, :integer
    field :buffed_battles_available, :integer, default: 0
  end

  def changeset(model, params \\ %{}) do
    model
    |> cast(params, [
      :experience,
      :level,
      :leveled_up,
      :win_streak,
      :loss_streak,
      :wins,
      :losses,
      :ties,
      :gold,
      :pve_points,
      :pvp_points,
      :skill_levels_available,
      :league_step,
      :previous_league_step,
      :league_tier,
      :pvp_wins,
      :pvp_losses,
      :pvp_ranking,
      :buffed_battles_available
    ])
  end
end
