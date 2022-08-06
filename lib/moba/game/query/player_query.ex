defmodule Moba.Game.Query.PlayerQuery do
  @moduledoc """
  Query functions for retrieving Players
  """

  alias Moba.Game
  alias Game.Schema.Player
  alias Game.Query.HeroQuery

  import Ecto.Query

  @maximum_points_difference Moba.maximum_points_difference()

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

  def limit_by(query, limit) do
    from _ in query, limit: ^limit
  end

  def random(query) do
    from _ in query, order_by: fragment("RANDOM()")
  end

  def ranking(limit) do
    from(player in limit_by(Player, limit),
      where: not is_nil(player.ranking),
      order_by: [asc: player.ranking]
    )
  end

  def eligible_for_ranking(limit) do
    base = non_bots() |> non_guests() |> limit_by(limit)

    from(player in base,
      order_by: [desc: [player.pvp_points, player.pve_tier, player.total_farm]]
    )
  end

  def by_ranking(query, min, max) do
    from player in query,
      where: player.ranking >= ^min,
      where: player.ranking <= ^max,
      order_by: [asc: player.ranking]
  end

  def by_pvp_points(query \\ Player) do
    from(player in query, order_by: [desc: player.pvp_points])
  end

  def eligible_arena_bots do
    bots() |> by_pvp_points()
  end

  def bot_opponents(pvp_tier) do
    from bot in bots(),
      where: bot.pvp_tier <= ^pvp_tier + 1,
      order_by: [desc: bot.pvp_points]
  end

  def normal_opponents(pvp_tier, player_points) do
    from player in available_opponents(),
      where: player.pvp_tier <= ^pvp_tier,
      where: player.pvp_points > ^player_points - @maximum_points_difference,
      order_by: [desc: player.pvp_points]
  end

  def elite_opponents(pvp_tier, player_points) do
    from player in available_opponents(),
      where: player.pvp_tier >= ^pvp_tier,
      where: player.pvp_points < ^player_points + @maximum_points_difference,
      order_by: [asc: player.pvp_points]
  end

  def auto_matchmaking do
    base = non_bots() |> available_opponents() |> random() |> limit_by(1)
    ago = Timex.now() |> Timex.shift(days: -1)

    from player in base, join: user in assoc(player, :user), where: user.last_online_at < ^ago
  end

  def matchmaking_bot(timestamp) do
    base = bots() |> random() |> limit_by(1)

    from bot in base,
      where: is_nil(bot.last_challenge_at) or bot.last_challenge_at < ^timestamp
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

  defp available_opponents(query \\ Player) do
    from player in query,
      where: player.pvp_points > 0,
      where: not is_nil(player.user_id) or not is_nil(player.bot_options)
  end
end
