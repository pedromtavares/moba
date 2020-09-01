defmodule Moba.Game.Query.ItemQuery do
  @moduledoc """
  Query functions for retrieving Items
  """

  alias Moba.Game
  alias Game.Schema.Item

  import Ecto.Query, only: [from: 2]

  def base_current do
    current() |> enabled()
  end

  def base_canon do
    canon() |> enabled() |> by_name()
  end

  def get_all(query, ids) do
    from item in query, where: item.id in ^ids
  end

  def canon(query \\ Item) do
    from s in query, where: is_nil(s.match_id)
  end

  def enabled(query \\ Item) do
    from s in query, where: s.enabled == true
  end

  def current(query \\ Item) do
    match = Game.current_match() || Game.last_match()
    from s in query, where: s.match_id == ^match.id
  end

  def by_name(query) do
    from item in query,
      order_by: item.name
  end
end
