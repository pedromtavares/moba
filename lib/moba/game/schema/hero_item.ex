defmodule Moba.Game.Schema.HeroItem do
  @moduledoc """
  Join table between Hero and Item
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias Moba.Game.Schema.{Hero, Item}

  schema "heroes_items" do
    belongs_to :hero, Hero
    belongs_to :item, Item

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :hero_id,
      :item_id
    ])
  end
end
