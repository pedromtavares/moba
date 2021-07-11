defmodule Moba.Game.Schema.Skin do
  @moduledoc """
  Represents a cosmetic image that can be assigned to a hero when entering the Arena

  Skins can be unlocked with shards, and can be of different league_tiers (Master/Grandmaster)
  """
  use Ecto.Schema
  use Arc.Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder, except: [:__meta__]}

  schema "skins" do
    field :background, Moba.Background.Type

    field :name, :string
    field :code, :string
    field :avatar_code, :string
    field :author_name, :string
    field :author_link, :string
    field :league_tier, :integer

    timestamps()
  end

  def changeset(skin, attrs) do
    skin
    |> cast(attrs, [
      :name,
      :code,
      :avatar_code,
      :author_name,
      :author_link,
      :league_tier
    ])
    |> cast_attachments(attrs, [:background])
  end
end
