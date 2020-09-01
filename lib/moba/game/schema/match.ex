defmodule Moba.Game.Schema.Match do
  @moduledoc """
  The highest level gameplay Schema, serving as a sort of container for other schemas.

  Matches run for a day and duplicates all 'canon' resources once it is generated,
  meaning that they cannot be edited after the match starts.

  Once a match ends, winners are assigned and a new one is started.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Moba.{Engine, Game}

  schema "matches" do
    field :active, :boolean, default: false
    field :last_server_update_at, :utc_datetime
    field :last_pvp_round_at, :utc_datetime
    field :next_changelog, :string
    field :winners, :map, default: %{}

    has_many :heroes, Game.Schema.Hero
    has_many :battles, Engine.Schema.Battle

    # duplicates 'canon' versions of these, not allowing them to be edited
    has_many :avatars, Game.Schema.Avatar
    has_many :items, Game.Schema.Item
    has_many :skills, Game.Schema.Skill

    timestamps()
  end

  def changeset(match, attrs) do
    match
    |> cast(attrs, [:active, :last_server_update_at, :next_changelog, :last_pvp_round_at, :winners])
  end
end
