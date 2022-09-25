defmodule Moba.Engine.Schema.Battle do
  @moduledoc """
  Battle schema that also embeds snapshots of both battlers and any rewards won
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Moba.{Engine, Game}
  alias Game.Schema.{Duel, Hero, Match}

  schema "battles" do
    belongs_to :attacker, Hero
    belongs_to :defender, Hero
    belongs_to :winner, Hero
    belongs_to :initiator, Hero
    belongs_to :duel, Duel
    belongs_to :match, Match

    field :type, :string
    field :difficulty, :string
    field :finished, :boolean

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
    |> cast(attrs, [:difficulty, :finished, :duel_id])
    |> cast_embed(:rewards)
    |> cast_embed(:attacker_snapshot)
    |> cast_embed(:defender_snapshot)
    |> change(%{winner_id: winner_id, initiator_id: initiator_id})
  end
end
