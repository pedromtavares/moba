defmodule Moba do
  @moduledoc """
  Cross-domain orchestration and higher level operations
  """

  alias Moba.{Accounts, Constants, Game, Ranker}

  use Constants

  defdelegate basic_attack, to: Game
  defdelegate evade, to: Game

  def cached_items do
    %{resource_uuid: uuid} = Game.current_season()

    case Cachex.get(:game_cache, "items-#{uuid}") do
      {:ok, nil} ->
        items = Game.shop_list()
        Cachex.put(:game_cache, "items-#{uuid}", items)
        items

      {:ok, items} ->
        items
    end
  end

  def can_shard_buyback?(%{player: %{user: %{shard_count: count}}} = hero) do
    Game.can_shard_buyback?(hero) && count >= shard_buyback_price(count) && count
  end

  def can_shard_buyback?(_), do: false

  defdelegate current_season, to: Game

  def load_resource(nil), do: nil
  def load_resource(code), do: Enum.find(cached_resources(), &(&1.code == code))
  def load_resource(code, nil), do: load_resource(code)
  def load_resource(code, level), do: Enum.find(cached_resources(), &(&1.code == code && &1.level == level))

  def player_for(%{id: user_id}) do
    with existing when existing != nil <- Game.get_player_from_user!(user_id) do
      existing
    else
      _ ->
        %{id: player_id} = Game.create_player!(%{user_id: user_id})
        Game.get_player!(player_id)
    end
  end

  def pve_ranking_available, do: cached_ranking("pve_ranking_available", fn -> Game.available_top_heroes() end)

  def pve_ranking, do: cached_ranking("pve_ranking", fn -> Game.pve_ranking(@pve_ranking_limit) end)

  def daily_ranking, do: cached_ranking("daily_ranking", fn -> Game.daily_ranking(@daily_ranking_limit) end)

  def season_ranking, do: cached_ranking("season_ranking", fn -> Game.season_ranking(@season_ranking_limit) end)

  def reward_shards!(%{user: %{shard_count: current_count} = user}, shard_reward) do
    Accounts.update_user!(user, %{shard_count: current_count + shard_reward})
  end

  def reward_shards!(player, _), do: player

  def shard_buyback!(%{player: %{user: %{shard_count: count} = user}} = hero) do
    if can_shard_buyback?(hero) do
      price = shard_buyback_price(count)
      Accounts.update_user!(user, %{shard_count: count - price})
      Game.shard_buyback!(hero)
    else
      hero
    end
  end

  def shard_buyback_price(shard_count) do
    minimum = shard_buyback_minimum()
    percentage_price = trunc(shard_count * minimum / 100)

    if percentage_price > minimum do
      percentage_price
    else
      minimum
    end
  end

  defdelegate unlocked_codes_for(user), to: Accounts

  @doc """
  Game pve_ranking is defined by which hero has the highest total_farm (gold + xp)
  """
  def rank_finished_heroes do
    if test?(), do: Game.rank_finished_heroes!(), else: GenServer.cast(Ranker, :pve)
  end

  @doc """
  Game pvp_ranking is defined by which player has the highest pvp_points
  """
  def update_pvp_rankings do
    if test?(), do: Game.update_daily_ranking!() && Game.update_season_ranking!(), else: GenServer.cast(Ranker, :pvp)
  end

  defp cached_ranking(key, fetch_fn) do
    case Cachex.get(:game_cache, key) do
      {:ok, nil} -> fetch_fn.()
      {:ok, ranking} -> ranking
    end
  end

  defp cached_resources do
    %{resource_uuid: uuid} = Game.current_season()

    case Cachex.get(:game_cache, "resources-#{uuid}") do
      {:ok, nil} ->
        resources = Game.shop_list() ++ Game.list_all_current_avatars() ++ Game.list_all_current_skills() ++ [evade()]
        Cachex.put(:game_cache, "resources-#{uuid}", resources)
        resources

      {:ok, resources} ->
        resources
    end
  end

  defp test?, do: Application.get_env(:moba, :env) == :test
end
