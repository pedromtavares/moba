defmodule Moba.Accounts.Query.UserQuery do
  @moduledoc """
  Query functions for retrieving Users
  """

  alias Moba.Accounts
  alias Accounts.Schema.User

  import Ecto.Query, only: [from: 2]

  def new_users(query \\ User, since_hours_ago \\ 24) do
    ago = Timex.now() |> Timex.shift(hours: -since_hours_ago)

    from(user in query, where: user.inserted_at > ^ago)
  end

  def non_bots(query \\ User) do
    from(user in query, where: user.is_bot == false)
  end

  def non_guests(query \\ User) do
    from(user in query, where: user.is_guest == false)
  end

  def online_users(query \\ User, hours_ago \\ 1) do
    ago = Timex.now() |> Timex.shift(hours: -hours_ago)

    from(user in query, where: user.last_online_at > ^ago)
  end

  def set_online_query(user) do
    from(u in User, where: u.id == ^user.id)
  end

  def ranking(limit) do
    from(user in User,
      where: not is_nil(user.ranking),
      order_by: [asc: user.ranking],
      limit: ^limit
    )
  end

  def eligible_for_ranking(limit) do
    from(u in User,
      order_by: [desc: [u.medal_count, u.level, u.experience]],
      where: u.is_bot == false,
      where: u.is_guest == false,
      limit: ^limit
    )
  end

  def by_pvp_points do
    from(u in User, order_by: [desc: u.pvp_points])
  end

  def with_pvp_points do
    from(u in by_pvp_points(), where: u.pvp_points > 0)
  end

  def eligible_arena_bots do
    from(u in by_pvp_points(),
      where: u.is_bot == true,
      where: is_nil(u.current_pvp_hero_id)
    )
  end

  def current_players do
    from(u in User,
      where: not is_nil(u.current_pve_hero_id) or not is_nil(u.current_pvp_hero_id)
    )
  end
end
