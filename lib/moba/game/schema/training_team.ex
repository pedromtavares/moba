defmodule Moba.Game.Schema.TrainingTeam do
  @moduledoc "An independent three-hero training draft and run."
  use Ecto.Schema

  schema "training_teams" do
    belongs_to :user, Moba.Accounts.Schema.User
    belongs_to :player, Moba.Game.Schema.Player
    field :name, :string
    field :state, :binary
    field :phase, :string
    field :turn, :integer, default: 1
    field :lock_version, :integer, default: 1
    field :finished_at, :utc_datetime
    field :archived_at, :utc_datetime
    field :total_farm, :integer
    field :duration_seconds, :integer
    field :league_tier, :integer
    field :hero_ids, {:array, :integer}, default: []
    has_many :heroes, Moba.Game.Schema.Hero
    has_many :encounters, Moba.Game.Schema.TeamEncounter, foreign_key: :team_run_id
    timestamps()
  end
end
