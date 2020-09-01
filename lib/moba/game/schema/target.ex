defmodule Moba.Game.Schema.Target do
  @moduledoc """
  Targets are what Heroes battle against in the Jungle (PVE),
  they are automatically generated after every battle according
  to their difficulty.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Moba.Game

  schema "targets" do
    field :difficulty, :string

    belongs_to :attacker, Game.Schema.Hero
    belongs_to :defender, Game.Schema.Hero

    timestamps()
  end

  def changeset(target, attrs) do
    target
    |> cast(attrs, [
      :difficulty
    ])
  end
end
