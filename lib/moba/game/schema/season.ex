defmodule Moba.Game.Schema.Season do
  @moduledoc """
  The highest level gameplay Schema, serving as a sort of container for other schemas.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Moba.Game

  schema "seasons" do
    field :title, :string
    field :active, :boolean, default: false
    field :last_server_update_at, :utc_datetime
    field :changelog, :string
    field :resource_uuid, :string

    has_many :players, Game.Schema.Player

    timestamps()
  end

  def changeset(season, attrs) do
    season
    |> cast(attrs, [:title, :active, :last_server_update_at, :changelog, :resource_uuid])
  end
end
