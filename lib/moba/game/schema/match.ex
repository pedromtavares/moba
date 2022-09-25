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
    field :phase_changed_at, :utc_datetime

    field :player_picks, {:array, :integer}
    field :opponent_picks, {:array, :integer}
    field :generated_picks, {:array, :integer}

    embeds_one :rewards, Engine.Schema.Rewards, on_replace: :update

    belongs_to :player, Player
    belongs_to :opponent, Player
    belongs_to :winner, Player

    timestamps()
  end

  def changeset(duel, attrs) do
    duel
    |> cast(attrs, [
      :player_picks,
      :opponent_picks,
      :generated_picks,
      :type,
      :phase,
      :phase_changed_at,
      :player_id,
      :opponent_id,
      :winner_id
    ])
    |> cast_embed(:rewards)
  end
end
