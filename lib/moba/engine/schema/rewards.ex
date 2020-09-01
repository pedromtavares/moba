defmodule Moba.Engine.Schema.Rewards do
  @moduledoc """
  Used to store all possible rewards a hero can get when a battle finishes
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :total_xp, :integer, default: 0
    field :battle_xp, :integer, default: 0
    field :win_xp, :integer, default: 0
    field :win_streak_xp, :integer, default: 0
    field :loss_streak_xp, :integer, default: 0
    field :difficulty_percentage, :integer, default: 0
    field :total_gold, :integer, default: 0
    field :total_pve_points, :integer, default: 0
    field :total_pvp_battles, :integer, default: 0
    field :attacker_pvp_points, :integer, default: 0
    field :defender_pvp_points, :integer, default: 0
  end

  def changeset(model, params \\ %{}) do
    model
    |> cast(params, [
      :total_gold,
      :total_xp,
      :battle_xp,
      :win_xp,
      :win_streak_xp,
      :loss_streak_xp,
      :difficulty_percentage,
      :total_pve_points,
      :total_pvp_battles,
      :attacker_pvp_points,
      :defender_pvp_points
    ])
  end
end
