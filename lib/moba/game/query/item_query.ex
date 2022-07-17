defmodule Moba.Game.Query.ItemQuery do
  @moduledoc """
  Query functions for retrieving Items
  """

  alias Moba.Game
  alias Game.Schema.{Item, HeroItem}

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
    from s in query, where: is_nil(s.resource_uuid)
  end

  def enabled(query \\ Item) do
    from s in query, where: s.enabled == true
  end

  def current(query \\ Item) do
    from s in query, where: s.current == true
  end

  def non_current(query \\ Item) do
    from s in query, where: s.current == false
  end

  def single_current(query \\ Item) do
    from s in current(query), order_by: [desc: s.id], limit: 1
  end

  def by_name(query) do
    from item in query,
      order_by: item.name
  end

  def with_code(query, code) do
    from item in query, where: item.code == ^code
  end

  def exclude(query, ids) do
    from s in query, where: s.id not in ^ids
  end

  def hero_items_by_item_ids(ids) do
    from hi in HeroItem, where: hi.item_id in ^ids
  end
end
