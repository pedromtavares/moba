defmodule Moba.Game.Schema.Build do
  @moduledoc """
  Build represent a battle strategy one can use to defeat oppoennts.

  Hero -> Build -> Skills

  While in the Jungle (PVE), a Hero can only have one Build, but once
  moving to the Arena (PVP), another Build can be created.

  Each Build may also store different skill and item orders, useful when
  defending in the Arena.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Moba.Game

  schema "builds" do
    field :type, :string
    field :skill_order, {:array, :string}
    field :item_order, {:array, :string}

    belongs_to :hero, Game.Schema.Hero

    many_to_many :skills, Game.Schema.Skill, join_through: Game.Schema.BuildSkill, on_replace: :delete

    timestamps()
  end

  def changeset(build, attrs) do
    build
    |> cast(attrs, [
      :type,
      :skill_order,
      :item_order
    ])
  end

  def create_changeset(build, attrs, hero, skills) do
    build
    |> changeset(attrs)
    |> put_assoc(:skills, skills)
    |> put_assoc(:hero, hero)
  end

  def replace_skills(build, skills) do
    build
    |> changeset(%{})
    |> put_assoc(:skills, skills)
  end
end
