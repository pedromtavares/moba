defmodule Moba.Game.Schema.BuildSkill do
  @moduledoc """
  Join table between Build and Skills
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias Moba.Game.Schema.{Build, Skill}

  schema "builds_skills" do
    belongs_to :build, Build
    belongs_to :skill, Skill

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :build_id,
      :skill_id
    ])
  end
end
