defmodule Moba.Game.Query.AvatarQuery do
  @moduledoc """
  Query functions for retrieving Avatars
  """

  alias Moba.Game
  alias Game.Schema.Avatar

  import Ecto.Query, only: [from: 2]

  def all_current do
    current() |> enabled()
  end

  def base_current do
    all_current() |> no_level_requirement()
  end

  def base_canon do
    canon() |> enabled() |> by_name()
  end

  def canon(query \\ Avatar) do
    from avatar in query, where: is_nil(avatar.resource_uuid)
  end

  def current(query \\ Avatar) do
    from avatar in query, where: avatar.current == true
  end

  def non_current(query \\ Avatar) do
    from avatar in query, where: avatar.current == false
  end

  def single_current(query \\ Avatar) do
    from avatar in current(query), order_by: [desc: avatar.id], limit: 1
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

  def with_code(query, code) do
    from avatar in query, where: avatar.code == ^code
  end

  def with_codes(query, codes) do
    from avatar in query, where: avatar.code in ^codes
  end

  def with_role(query, role) do
    from avatar in query, where: avatar.role == ^role
  end

  def by_name(query) do
    from avatar in query, order_by: avatar.name
  end

  def exclude(query, ids) do
    from avatar in query, where: avatar.id not in ^ids
  end
end
