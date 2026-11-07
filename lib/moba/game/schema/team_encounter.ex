defmodule Moba.Game.Schema.TeamEncounter do
  @moduledoc "A replayable farming battle, league challenge or Roshan encounter."
  use Ecto.Schema

  schema "team_encounters" do
    belongs_to :team_run, Moba.Game.Schema.TrainingTeam
    field :turn, :integer
    field :label, :string
    field :state, :binary, virtual: true
    timestamps(updated_at: false)
  end
end
