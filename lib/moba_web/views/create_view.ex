defmodule MobaWeb.CreateView do
  use MobaWeb, :view

  def selected_skills(skills) do
    skills
    |> Enum.map(fn skill -> skill.name end)
    |> Enum.join(", ")
  end

  def active_skills(skills) do
    Enum.filter(skills, fn skill -> !skill.passive end)
    |> Enum.sort_by(fn skill -> skill.mp_cost end)
  end

  def passive_skills(skills) do
    Enum.filter(skills, fn skill -> skill.passive end)
  end

  def role(%{role: role}) when not is_nil(role), do: String.capitalize(role)
  def role(_), do: ""

  def role_description(%{role: role}) do
    case role do
      "tank" -> "High defense for sustained damage absorption."
      "bruiser" -> "Tankier than most, good offense."
      "nuker" -> "Obliterate opponents with constant spellcasting."
      "carry" -> "Swift destruction."
      "support" -> "Tactical spellcasting for elegant victories."
      _ -> ""
    end
  end

  def display_percentage(:offense, avatar, avatars) do
    max = Enum.max_by(avatars, fn avatar -> avatar.display_offense end)

    avatar.display_offense * 100 / max.display_offense
  end

  def display_percentage(:defense, avatar, avatars) do
    max = Enum.max_by(avatars, fn avatar -> avatar.display_defense end)

    avatar.display_defense * 100 / max.display_defense
  end

  def display_percentage(:magic, avatar, avatars) do
    max = Enum.max_by(avatars, fn avatar -> avatar.display_magic end)

    avatar.display_magic * 100 / max.display_magic
  end

  def display_percentage(:speed, avatar, avatars) do
    max = Enum.max_by(avatars, fn avatar -> avatar.display_speed end)

    avatar.display_speed * 100 / max.display_speed
  end

  def builds_for(role), do: Game.skill_builds_for(role)

  def build_for(role, index), do: Game.skill_build_for(role, index)

  def build_title(_, selected_skills, nil) when length(selected_skills) > 0, do: "Custom Build"
  def build_title(_, _, nil), do: "Skill Build"

  def build_title(avatar, _, index) do
    build = build_for(avatar.role, index)
    elem(build, 1)
  end
end
