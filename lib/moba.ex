defmodule Moba do
  @moduledoc """
  High-level helpers, core variables and cross-context orchestration
  """

  alias Moba.{Game, Accounts, Conductor, Cleaner}

  # General constants
  @initial_battles 30
  @xp_boosted_battles 30
  @initial_gold 1000
  @items_base_price 400
  @max_battle_turns 12
  @damage_types %{normal: "normal", magic: "magic", pure: "pure"}
  @user_level_xp 5000
  @leagues %{
    0 => "Bronze League",
    1 => "Silver League",
    2 => "Gold League",
    3 => "Platinum League",
    4 => "Diamond League",
    5 => "Master League",
    6 => "Grandmaster League"
  }
  @medals %{
    0 => "Herald",
    1 => "Guardian",
    2 => "Crusader",
    3 => "Archon",
    4 => "Legend",
    5 => "Ancient",
    6 => "Divine",
    7 => "Immortal"
  }
  @easy_mode_count 2
  @easy_mode_max_farm 20_000

  # PVE constants
  @base_xp 100
  @xp_increment 20
  @battle_xp 50
  @pve_points_limit 12
  @max_hero_level 25
  @shard_limit 200

  # PVP constants
  @pvp_heroes_per_page 3
  @ranking_heroes_per_page 10
  @pvp_timeout_in_hours 24
  @pvp_round_decay 25
  @pvp_round_timeout_in_hours 12
  @season_points_per_medal 25
  @max_season_tier 7

  # League constants
  @master_league_tier 5
  @max_league_tier 6
  @league_win_gold_bonus 2000
  @league_win_buffed_battles_bonus 3
  @league_buff_multiplier 0.5
  @boss_regeneration_multiplier 0.5
  @boss_win_gold_bonus 4000
  @buyback_gold_penalty 2000

  def initial_battles, do: @initial_battles
  def xp_boosted_battles, do: @xp_boosted_battles
  def initial_gold, do: @initial_gold
  def items_base_price, do: @items_base_price
  def normal_items_price, do: @items_base_price * 1
  def rare_items_price, do: @items_base_price * 3
  def epic_items_price, do: @items_base_price * 6
  def legendary_items_price, do: @items_base_price * 12
  def max_battle_turns, do: @max_battle_turns
  def damage_types, do: @damage_types
  def user_level_xp, do: @user_level_xp
  def leagues, do: @leagues
  def medals, do: @medals
  def easy_mode_count, do: @easy_mode_count
  def easy_mode_max_farm, do: @easy_mode_max_farm

  def base_xp, do: @base_xp
  def xp_increment, do: @xp_increment
  def battle_xp, do: @battle_xp
  def pve_points_limit, do: @pve_points_limit
  def max_hero_level, do: @max_hero_level
  def shard_limit, do: @shard_limit

  def pvp_heroes_per_page, do: @pvp_heroes_per_page
  def ranking_heroes_per_page, do: @ranking_heroes_per_page
  def pvp_timeout_in_hours, do: @pvp_timeout_in_hours
  def pvp_round_decay, do: @pvp_round_decay
  def pvp_round_timeout_in_hours, do: @pvp_round_timeout_in_hours
  def season_points_per_medal, do: @season_points_per_medal
  def max_season_tier, do: @max_season_tier

  def master_league_tier, do: @master_league_tier
  def max_league_tier, do: @max_league_tier
  def league_win_gold_bonus, do: @league_win_gold_bonus
  def league_win_buffed_battles_bonus, do: @league_win_buffed_battles_bonus
  def league_buff_multiplier, do: @league_buff_multiplier
  def boss_regeneration_multiplier, do: @boss_regeneration_multiplier
  def boss_win_gold_bonus, do: @boss_win_gold_bonus
  def buyback_gold_penalty, do: @buyback_gold_penalty

  def win_streak_xp(streak) when streak > 1 do
    amount = (streak - 1) * 10
    if amount > 100, do: 100, else: amount
  end

  def win_streak_xp(_), do: 0

  def loss_streak_xp(streak) when streak > 1, do: (streak - 1) * 30
  def loss_streak_xp(_), do: 0

  def xp_percentage("weak"), do: 70
  def xp_percentage("moderate"), do: 100
  def xp_percentage("strong"), do: 200

  def streak_percentage("weak"), do: 50
  def streak_percentage("moderate"), do: 100
  def streak_percentage("strong"), do: 150

  def victory_pve_points("weak"), do: 2
  def victory_pve_points("moderate"), do: 4
  def victory_pve_points("strong"), do: 6

  def tie_pve_points("weak"), do: 1
  def tie_pve_points("moderate"), do: 2
  def tie_pve_points("strong"), do: 3

  # diff = defender.pvp_points - attacker.pvp_points

  def attacker_win_pvp_points(diff) when diff < -40, do: 2
  def attacker_win_pvp_points(diff), do: round(5 + (diff + 80) * 0.05)

  def attacker_loss_pvp_points(diff) when diff > 40, do: -2
  def attacker_loss_pvp_points(diff), do: round(-5 + (diff - 80) * 0.05)

  def defender_win_pvp_points(diff) when diff > 40, do: 0
  def defender_win_pvp_points(diff), do: -round((diff - 40) * 0.05)

  def defender_loss_pvp_points(diff) when diff < -40, do: 0
  def defender_loss_pvp_points(diff), do: -round((diff + 40) * 0.05)

  def avatar_minimum_stats() do
    %{
      total_hp: 200,
      total_mp: 10,
      atk: 12,
      power: 0,
      armor: 0,
      speed: 0
    }
  end

  def avatar_stat_units() do
    %{
      total_hp: 5,
      total_mp: 4,
      atk: 1,
      power: 1.4,
      armor: 1,
      speed: 5
    }
  end

  def xp_to_next_hero_level(level) when level < 1, do: 0
  def xp_to_next_hero_level(level) when level > 20, do: trunc(base_xp_calculation(level) * 1.5)
  def xp_to_next_hero_level(level), do: base_xp_calculation(level)
  defp base_xp_calculation(level), do: base_xp() + (level - 1) * xp_increment()

  def xp_until_hero_level(level) when level < 2, do: 0
  def xp_until_hero_level(level), do: xp_to_next_hero_level(level) + xp_until_hero_level(level - 1)

  def start! do
    IO.puts("Starting match...")
    Conductor.start_match!()
    Cleaner.cleanup_old_records()
  end

  def current_match, do: Game.current_match()

  def create_current_pve_hero!(
        attrs,
        user,
        avatar,
        skills,
        match \\ current_match()
      ) do
    attrs =
      if Accounts.easy_mode?(user) do
        Map.merge(attrs, %{easy_mode: true, pve_battles_available: 1000})
      else
        attrs
      end

    Accounts.maybe_archive_current_pve_hero(user)
    hero = Game.create_hero!(attrs, user, avatar, skills, match)
    Accounts.set_current_pve_hero!(user, hero.id)
    hero
  end

  def prepare_current_pvp_hero!(hero) do
    Accounts.set_current_pvp_hero!(hero.user, hero.id)
    Game.prepare_hero_for_pvp!(hero)
  end

  def update_attacker!(hero, updates) do
    Accounts.user_pvp_updates!(hero.user_id, updates)
    Game.update_attacker!(hero, updates)
  end

  def update_defender!(hero, updates) do
    Accounts.user_pvp_updates!(hero.user_id, updates)
    Game.update_hero!(hero, updates)
  end

  @doc """
  Game pvp_ranking is defined by who currently have the highest pvp_points
  Game pve_ranking is defined by who has the highest total_farm (gold)
  Accounts ranking is defined by who has the highest medal_count
  """
  def update_rankings! do
    Game.update_pvp_ranking!()
    Game.update_pve_ranking!()
    Accounts.update_ranking!()
  end

  def basic_attack, do: Game.basic_attack()

  def add_user_experience(user, experience), do: Accounts.add_user_experience(user, experience)

  def update_user!(user, updates), do: Accounts.update_user!(user, updates)

  def struct_from_map(a_map, as: a_struct) do
    # Find the keys within the map
    keys =
      Map.keys(a_struct)
      |> Enum.filter(fn x -> x != :__struct__ end)

    # Process map, checking for both string / atom keys
    processed_map =
      for key <- keys, into: %{} do
        value = Map.get(a_map, key) || Map.get(a_map, to_string(key))
        {key, value}
      end

    a_struct = Map.merge(a_struct, processed_map)
    a_struct
  end

  def run_async(fun) do
    if Application.get_env(:moba, :env) == :test do
      fun.()
    else
      Task.start(fun)
    end
  end
end
