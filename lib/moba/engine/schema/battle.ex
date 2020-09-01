defmodule Moba.Engine.Schema.Battle do
  @moduledoc """
  Battle schema that also embeds snapshots of both battlers and any rewards won
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Moba.{Engine, Game}

  schema "battles" do
    belongs_to :match, Game.Schema.Match
    belongs_to :attacker, Game.Schema.Hero
    belongs_to :defender, Game.Schema.Hero
    belongs_to :winner, Game.Schema.Hero
    belongs_to :initiator, Game.Schema.Hero

    field :type, :string
    field :difficulty, :string
    field :finished, :boolean
    field :unread_id, :integer

    embeds_one :rewards, Engine.Schema.Rewards, on_replace: :update
    embeds_one :attacker_snapshot, Engine.Schema.HeroSnapshot, on_replace: :update
    embeds_one :defender_snapshot, Engine.Schema.HeroSnapshot, on_replace: :update

    has_many :turns, Engine.Schema.Turn

    timestamps()
  end

  def changeset(%{winner: winner, initiator: initiator} = battle, attrs) do
    winner_id = winner && winner.id
    initiator_id = initiator && initiator.id

    battle
    |> cast(attrs, [:difficulty, :finished, :unread_id, :match_id])
    |> cast_embed(:rewards)
    |> cast_embed(:attacker_snapshot)
    |> cast_embed(:defender_snapshot)
    |> change(%{winner_id: winner_id, initiator_id: initiator_id})
  end
end
