defmodule Moba.Game.Query.AvatarQuery do
  @moduledoc """
  Query functions for retrieving Avatars
  """

  alias Moba.Game
  alias Game.Schema.Avatar

  import Ecto.Query, only: [from: 2]

  def base_current do
    current() |> enabled() |> no_level_requirement()
  end

  def base_canon do
    canon() |> enabled() |> by_name()
  end

  def all_current do
    current() |> enabled()
  end

  def canon(query \\ Avatar) do
    from avatar in query, where: is_nil(avatar.match_id)
  end

  def current(query \\ Avatar) do
    match = Game.current_match()
    from avatar in query, where: avatar.match_id == ^match.id
  end

  def enabled(query \\ Avatar) do
    from avatar in query, where: avatar.enabled == true
  end

  def no_level_requirement(query \\ Avatar) do
    from avatar in query, where: is_nil(avatar.level_requirement)
  end

  def with_level_requirement(query \\ Avatar) do
    from avatar in query,
      where: not is_nil(avatar.level_requirement),
      order_by: [asc: avatar.level_requirement]
  end

  def with_codes(query, codes) do
    from avatar in query, where: avatar.code in ^codes
  end

  def by_name(query) do
    from avatar in query, order_by: avatar.name
  end
end
