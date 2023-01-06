defmodule Moba.Game.Schema.Team do
  @moduledoc """
  Represents a group of heroes used in the PvP Arena
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Moba.Game

  schema "teams" do
    field :name, :string
    field :defensive, :boolean, default: false
    field :pick_ids, {:array, :integer}, default: []
    field :used_count, :integer, default: 0

    belongs_to :player, Game.Schema.Player

    timestamps()
  end

  def changeset(team, attrs) do
    team
    |> cast(attrs, [:name, :defensive, :pick_ids, :used_count, :player_id])
  end
end
