defmodule Moba.Game.Schema.HeroSkill do
  @moduledoc """
  Join table between Hero and Skill
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias Moba.Game.Schema.{Hero, Skill}

  schema "heroes_skills" do
    belongs_to :hero, Hero
    belongs_to :skill, Skill

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :hero_id,
      :skill_id
    ])
  end
end
