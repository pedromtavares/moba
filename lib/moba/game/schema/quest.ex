defmodule Moba.Game.Schema.Quest do
  @moduledoc """
  Represents an objective that users can complete while playing
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "quests" do
    field :title, :string
    field :code, :string
    field :description, :string
    field :level, :integer
    field :shard_prize, :integer
    field :icon, :string
    field :initial_value, :integer, default: 0
    field :final_value, :integer
    field :daily, :boolean, default: false

    timestamps()
  end

  def changeset(quest, attrs) do
    quest
    |> cast(attrs, [
      :title,
      :code,
      :description,
      :level,
      :shard_prize,
      :icon,
      :initial_value,
      :final_value,
      :daily
    ])
  end
end
