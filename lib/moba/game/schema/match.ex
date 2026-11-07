defmodule Moba.Game.Schema.Match do
  @moduledoc """
  TODO: docthis
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Moba.{Engine, Game}
  alias Game.Schema.Player

  schema "matches" do
    field :phase, :string
    field :type, :string
    field :team_size, :integer, default: 3
    field :interactive, :boolean, default: false
    field :phase_changed_at, :utc_datetime

    field :player_picks, {:array, :integer}
    field :opponent_picks, {:array, :integer}
    field :generated_picks, {:array, :integer}

    embeds_one :rewards, Engine.Schema.Rewards, on_replace: :update

    belongs_to :player, Player
    belongs_to :opponent, Player
    belongs_to :winner, Player
    belongs_to :training_team, Game.Schema.TrainingTeam
    belongs_to :training_encounter, Game.Schema.TeamEncounter
    field :training_state, :binary
    has_many :battles, Engine.Schema.Battle

    timestamps()
  end

  def changeset(duel, attrs) do
    duel
    |> cast(attrs, [
      :player_picks,
      :opponent_picks,
      :generated_picks,
      :type,
      :interactive,
      :phase,
      :phase_changed_at,
      :player_id,
      :opponent_id,
      :winner_id
    ])
    |> cast_embed(:rewards)
  end
end
