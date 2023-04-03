defmodule Moba.Game.Query.PlayerQuery do
  @moduledoc """
  Query functions for retrieving Players
  """

  alias Moba.Game
  alias Game.Schema.Player
  alias Game.Query.HeroQuery

  @current_ranking_date Moba.current_ranking_date()

  import Ecto.Query

  def load(queryable \\ Player) do
    queryable
    |> preload([
      :user,
      current_pve_hero: ^HeroQuery.load()
    ])
  end

  def bots(query \\ Player) do
    from(player in query, where: not is_nil(player.bot_options))
  end

  def non_bots(query \\ Player) do
    from(player in query, where: is_nil(player.bot_options))
  end

  def non_guests(query \\ Player) do
    from(player in query, where: not is_nil(player.user_id))
  end

  def guests(query \\ Player) do
    from(player in query, where: is_nil(player.user_id))
  end

  def with_status(query \\ Player, status) do
    from(player in query, where: player.status == ^status)
  end

  def with_ids(query, ids) do
    from player in query, where: player.id in ^ids
  end

  def exclude_ids(query, ids) do
    from player in query, where: player.id not in ^ids
  end

  def exclude_rankings(query, rankings) do
    from player in query, where: player.ranking not in ^rankings
  end

  def limit_by(query, limit) do
    from _ in query, limit: ^limit
  end

  def random(query) do
    from _ in query, order_by: fragment("RANDOM()")
  end

  def daily_ranked(limit) do
    from(player in limit_by(Player, limit),
      where: not is_nil(player.ranking),
      order_by: [asc: player.ranking]
    )
    |> preload(:user)
  end

  def by_pvp_points(query \\ Player) do
    from(player in query, order_by: [desc: player.pvp_points])
  end

  def eligible_arena_bots do
    bots() |> by_pvp_points()
  end

  def old_ranking(limit) do
    base = non_bots() |> non_guests() |> limit_by(limit)

    from(player in base,
      order_by: [desc: [player.pvp_points, player.pve_tier, player.total_farm]]
    )
  end

  def season_ranked(limit) do
    from(player in limit_by(Player, limit),
      where: not is_nil(player.season_ranking),
      order_by: [asc: player.season_ranking]
    )
    |> preload(:user)
  end

  def season_ranking(limit) do
    base = non_bots() |> non_guests() |> limit_by(limit)

    from(player in base,
      join: user in assoc(player, :user),
      where: user.last_online_at > ^@current_ranking_date,
      order_by: [
        desc: fragment("(500 * ?) + (500 * ?) + ?", player.best_immortal_streak, player.pve_tier, player.pvp_points),
        desc: player.total_wins
      ]
    )
  end

  def with_pvp_tier(tier) do
    from player in pvp_available(), where: player.pvp_tier == ^tier
  end

  def by_daily_wins(query \\ Player) do
    from player in query, order_by: [desc: player.daily_wins, desc: player.pvp_points]
  end

  def matchmaking_opponents(id, pvp_tier, limit \\ 1) do
    from(player in pvp_available(), where: player.pvp_tier == ^pvp_tier)
    |> exclude_ids([id])
    |> random()
    |> limit_by(limit)
  end

  def pleb_opponents(id, pvp_points, limit \\ 5) do
    bottom = pvp_points - 100
    top = pvp_points + 200

    from(player in pvp_available(),
      where: player.pvp_tier == 0,
      where: player.pvp_points >= ^bottom,
      where: player.pvp_points <= ^top
    )
    |> exclude_ids([id])
    |> random()
    |> limit_by(limit)
  end

  def currently_active(query \\ Player, hours_ago \\ 24) do
    ago = Timex.now() |> Timex.shift(hours: -hours_ago)

    from player in query,
      join: user in assoc(player, :user),
      where: user.last_online_at > ^ago,
      order_by: [desc: user.last_online_at]
  end

  def recently_created(query \\ Player, since_hours_ago \\ 24) do
    ago = Timex.now() |> Timex.shift(hours: -since_hours_ago)

    from(player in query, where: player.inserted_at > ^ago, order_by: [desc: player.inserted_at])
  end

  def pvp_available(query \\ Player) do
    base = query |> non_bots() |> non_guests()

    from player in base, where: player.total_matches > 0
  end
end
