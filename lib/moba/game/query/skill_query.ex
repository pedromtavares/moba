defmodule Moba.Game.Query.SkillQuery do
  @moduledoc """
  Query functions for retrieving Skills
  """

  alias Moba.Game
  alias Game.Schema.Skill

  import Ecto.Query, only: [from: 2]

  def base_current do
    current() |> enabled()
  end

  def base_canon do
    canon() |> enabled() |> by_name()
  end

  def canon(query \\ Skill) do
    from s in query, where: is_nil(s.match_id)
  end

  def enabled(query \\ Skill) do
    from s in query, where: s.enabled == true
  end

  def current(query \\ Skill) do
    match = Game.current_match()
    from s in query, where: s.match_id == ^match.id
  end

  def get_all(query, ids) do
    from skill in query,
      where: skill.id in ^ids
  end

  def normals(query \\ Skill) do
    from skill in query,
      where: skill.ultimate == false
  end

  def ultimates(query \\ Skill) do
    from skill in query,
      where: skill.ultimate == true
  end

  def no_level_requirement(query \\ Skill) do
    from s in query, where: is_nil(s.level_requirement)
  end

  def with_level_requirement(query \\ Skill) do
    from s in query,
      where: not is_nil(s.level_requirement),
      order_by: s.level_requirement
  end

  def by_name(query) do
    from skill in query,
      order_by: skill.name
  end

  def by_mp_cost(query) do
    from skill in query,
      order_by: skill.mp_cost
  end

  def with_level(query, level) do
    from skill in query,
      where: skill.level == ^level
  end

  def with_code(query, code) do
    from skill in query,
      where: skill.code == ^code
  end

  def with_codes(query, codes) do
    from skill in query,
      where: skill.code in ^codes
  end

  def random(query) do
    from skill in query,
      order_by: fragment("RANDOM()")
  end

  def ordered(query \\ Skill) do
    from s in query,
      order_by: [asc: s.ultimate, asc: s.passive, asc: s.name]
  end
end
