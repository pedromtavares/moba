defmodule Moba.Game.Schema.ArenaPick do
  @moduledoc """
  Represents a choice that a user makes for which hero to play with in the daily Arena matches.
  """
  use Ecto.Schema
  use Arc.Ecto.Schema
  import Ecto.Changeset
  alias Moba.{Accounts, Game}

  schema "arena_picks" do
    field :points, :integer
    field :ranking, :integer
    field :wins, :integer
    field :losses, :integer

    belongs_to :user, Accounts.Schema.User
    belongs_to :match, Game.Schema.Match
    belongs_to :hero, Game.Schema.Hero

    timestamps()
  end

  def changeset(arena_pick, attrs) do
    arena_pick
    |> cast(attrs, [
      :points,
      :ranking,
      :wins,
      :losses
    ])
  end

  def create_changeset(arena_pick, attrs, user, hero, match) do
    arena_pick
    |> changeset(attrs)
    |> put_assoc(:user, user)
    |> put_assoc(:hero, hero)
    |> put_assoc(:match, match)
  end
end
