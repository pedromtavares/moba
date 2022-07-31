defmodule Moba.Engine.Schema.Turn do
  @moduledoc """
  Turn schema that stores the state of both battlers,
  keeping a clean record of how the Battle was processed
  """

  alias Moba.Engine

  use Ecto.Schema

  schema "turns" do
    belongs_to :battle, Engine.Schema.Battle

    field :number, :integer
    field :skill_code, :string
    field :item_code, :string

    field :orders, :map, virtual: true
    field :resource, :map, virtual: true
    field :final_effects, {:array, :map}, virtual: true, default: []

    field :skill, :map, virtual: true
    field :item, :map, virtual: true

    embeds_one :attacker, Engine.Schema.Battler
    embeds_one :defender, Engine.Schema.Battler

    timestamps()
  end
end
