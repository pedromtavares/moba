defmodule Moba.Accounts.Query.UserQuery do
  @moduledoc """
  Query functions for retrieving Users
  """

  alias Moba.Accounts
  alias Accounts.Schema.User

  import Ecto.Query

  @current_ranking_date Moba.current_ranking_date()

  def load(queryable \\ User) do
    queryable
  end

  def new_users(query \\ User, since_hours_ago \\ 24) do
    ago = Timex.now() |> Timex.shift(hours: -since_hours_ago)

    from(user in non_bots(query), where: user.inserted_at > ^ago)
  end

  def bots(query \\ User) do
    from(user in query, where: user.is_bot == true)
  end

  def non_bots(query \\ User) do
    from(user in query, where: user.is_bot == false)
  end

  def non_guests(query \\ User) do
    from(user in query, where: user.is_guest == false)
  end

  def guests(query \\ User) do
    from(user in query, where: user.is_guest == true)
  end

  def online_users(query \\ User, hours_ago \\ 1) do
    ago = Timex.now() |> Timex.shift(hours: -hours_ago)

    from(u in non_bots(query), where: u.last_online_at > ^ago)
  end

  def order_by_online(query) do
    from(u in query, order_by: [desc: u.last_online_at])
  end

  def online_before(days_ago) do
    base = non_bots() |> non_guests()
    ago = Timex.now() |> Timex.shift(days: -days_ago)

    from(u in base, where: u.last_online_at < ^ago)
  end

  def by_user(query \\ User, user) do
    from(u in query, where: u.id == ^user.id)
  end

  def with_status(query \\ User, status) do
    from(u in query, where: u.status == ^status)
  end

  def exclude_ids(query, ids) do
    from user in query, where: user.id not in ^ids
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
      order_by: [desc: [u.season_points, u.level, u.experience]],
      where: u.is_bot == false,
      where: u.is_guest == false,
      where: u.last_online_at > ^@current_ranking_date,
      limit: ^limit
    )
  end

  def by_ranking(query, min, max) do
    from user in query,
      where: user.ranking >= ^min,
      where: user.ranking <= ^max,
      order_by: [asc: user.ranking]
  end

  def by_level(query, level) do
    from user in query, where: user.level == ^level, order_by: fragment("RANDOM()")
  end

  def by_season_points do
    from(u in User, order_by: [desc: u.season_points])
  end

  def with_pvp_heroes(query \\ User) do
    from(u in query, where: not is_nil(u.current_pvp_hero_id))
  end

  def by_bot_tier(query, tier) do
    from(u in query, where: u.bot_tier == ^tier)
  end

  def eligible_arena_bots do
    from(u in by_season_points(), where: u.is_bot == true)
  end

  def matchmaking(season_tier) do
    from bot in bots(),
      where: bot.season_tier <= ^season_tier,
      order_by: [desc: bot.season_points]
  end

  def elite_matchmaking(season_tier) do
    from bot in bots(),
      where: bot.season_tier >= ^season_tier,
      order_by: [asc: bot.season_points]
  end

  def limit_by(query, limit) do
    from u in query, limit: ^limit
  end

  def random(query) do
    from user in query,
      order_by: fragment("RANDOM()")
  end

  def skynet_bot(timestamp) do
    base = bots() |> random() |> limit_by(1)

    from bot in base,
      where: is_nil(bot.last_online_at) or bot.last_online_at < ^timestamp
  end
end
