defmodule Moba do
  @moduledoc """
  High-level helpers, core variables and cross-context orchestration
  """

  alias Moba.{Game, Accounts, Conductor, Cleaner}

  # General constants
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
  @pve_tiers %{
    0 => "Initiate",
    1 => "Novice",
    2 => "Adept",
    3 => "Veteran",
    4 => "Expert",
    5 => "Master",
    6 => "Grandmaster",
    7 => "Invoker"
  }
  @turn_mp_regen_multiplier 0.01
  @final_tutorial_step 14
  @season_quest_codes ["season", "season_master", "season_grandmaster", "season_perfect"]

  # PVE constants
  @total_pve_turns 25
  @turns_per_tier 5
  @base_xp 600
  @xp_increment 50
  @veteran_pve_tier 2
  @initial_gold 800
  @veteran_initial_gold 2000
  @items_base_price 400
  @buyback_multiplier 10
  @refresh_targets_count 5
  @maximum_total_farm 60_000
  @seconds_per_turn 3
  @pve_win_bonus 100
  @max_pve_tier 7

  # PVP constants
  @pvp_heroes_per_page 3
  @ranking_heroes_per_page 10
  @pvp_timeout_in_hours 24
  @pvp_round_decay 25
  @pvp_round_timeout_in_hours 12
  @season_points_per_medal 25
  @max_season_tier 7

  # League constants
  @platinum_league_tier 3
  @master_league_tier 5
  @max_league_tier 6
  @league_win_bonus 2000
  @boss_regeneration_multiplier 0.5
  @boss_win_bonus 2000

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
  def pve_tiers, do: @pve_tiers
  def turn_mp_regen_multiplier, do: @turn_mp_regen_multiplier
  def final_tutorial_step, do: @final_tutorial_step
  def season_quest_codes, do: @season_quest_codes

  def total_pve_turns(0), do: @total_pve_turns - 10
  def total_pve_turns(1), do: @total_pve_turns - 5
  def total_pve_turns(_), do: @total_pve_turns
  def turns_per_tier, do: @turns_per_tier
  def base_xp, do: @base_xp
  def xp_increment, do: @xp_increment
  def veteran_pve_tier, do: @veteran_pve_tier
  def initial_gold(%{pve_tier: tier}) when tier > 0, do: @veteran_initial_gold
  def initial_gold(_), do: @initial_gold
  def buyback_multiplier, do: @buyback_multiplier
  def refresh_targets_count, do: @refresh_targets_count
  def maximum_total_farm, do: @maximum_total_farm
  def seconds_per_turn, do: @seconds_per_turn
  def pve_win_bonus, do: @pve_win_bonus
  def farm_per_turn(0), do: 800..1100
  def farm_per_turn(1), do: 850..1100
  def farm_per_turn(2), do: 900..1100
  def farm_per_turn(3), do: 950..1100
  def farm_per_turn(_), do: 1000..1100
  def battle_xp("weak", pve_tier) when pve_tier < @veteran_pve_tier, do: 400
  def battle_xp("moderate", pve_tier) when pve_tier < @veteran_pve_tier, do: 500
  def battle_xp("moderate", _), do: 400
  def battle_xp("strong", _), do: 500
  def max_pve_tier, do: @max_pve_tier

  def pvp_heroes_per_page, do: @pvp_heroes_per_page
  def ranking_heroes_per_page, do: @ranking_heroes_per_page
  def pvp_timeout_in_hours, do: @pvp_timeout_in_hours
  def pvp_round_decay, do: @pvp_round_decay
  def pvp_round_timeout_in_hours, do: @pvp_round_timeout_in_hours
  def season_points_per_medal, do: @season_points_per_medal
  def max_season_tier, do: @max_season_tier

  def platinum_league_tier, do: @platinum_league_tier
  def master_league_tier, do: @master_league_tier
  def max_league_tier, do: @max_league_tier
  def league_win_bonus, do: @league_win_bonus
  def league_buff_multiplier(0, league_tier) when league_tier < 3, do: 0.6
  def league_buff_multiplier(1, league_tier) when league_tier < 3, do: 0.45
  def league_buff_multiplier(2, league_tier) when league_tier < 3, do: 0.3
  def league_buff_multiplier(3, league_tier) when league_tier < 3, do: 0.15
  def league_buff_multiplier(_, _), do: 0
  def boss_regeneration_multiplier, do: @boss_regeneration_multiplier
  def boss_win_bonus, do: @boss_win_bonus
  def max_available_league(0), do: 4
  def max_available_league(1), do: 5
  def max_available_league(_), do: 6

  # diff = defender.pvp_points - attacker.pvp_points

  def attacker_win_pvp_points(diff, 6) when diff < -40, do: 2
  def attacker_win_pvp_points(diff, 6), do: round(5 + (diff + 80) * 0.05)
  def attacker_win_pvp_points(diff, _), do: div(attacker_win_pvp_points(diff, 6), 2)

  def attacker_loss_pvp_points(diff, 6) when diff > 40, do: -2
  def attacker_loss_pvp_points(diff, 6), do: round(-5 + (diff - 80) * 0.05)
  def attacker_loss_pvp_points(diff, _), do: div(attacker_loss_pvp_points(diff, 6), 2)

  def defender_win_pvp_points(diff, 6) when diff > 40, do: 0
  def defender_win_pvp_points(diff, 6), do: -round((diff - 40) * 0.05)
  def defender_win_pvp_points(diff, _), do: div(defender_win_pvp_points(diff, 6), 2)

  def defender_loss_pvp_points(diff, 6) when diff < -40, do: 0
  def defender_loss_pvp_points(diff, 6), do: -round((diff + 40) * 0.05)
  def defender_loss_pvp_points(diff, _), do: div(defender_loss_pvp_points(diff, 6), 2)

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
  def xp_to_next_hero_level(level), do: base_xp() + (level - 2) * xp_increment()

  def xp_until_hero_level(level) when level < 2, do: 0
  def xp_until_hero_level(level), do: xp_to_next_hero_level(level) + xp_until_hero_level(level - 1)

  def start! do
    IO.puts("Starting match...")
    Conductor.start_match!()
    Cleaner.cleanup_old_records()
  end

  def regenerate_resources! do
    IO.puts("Regenerating resources...")
    Conductor.regenerate_resources!()
  end

  def generate_bots!(bot_level_range \\ 0..35) do
    IO.puts("Generating new bots...")
    Conductor.generate_bots!(bot_level_range)
  end

  def current_match, do: Game.current_match()

  def create_current_pve_hero!(
        attrs,
        user,
        avatar,
        skills
      ) do
    hero = Game.create_hero!(attrs, user, avatar, skills)
    Accounts.set_current_pve_hero!(user, hero.id)
    hero
  end

  def prepare_current_pvp_hero!(hero) do
    Accounts.set_current_pvp_hero!(hero.user, hero.id)
    Game.prepare_hero_for_pvp!(hero)
  end

  @doc """
  Game pvp_ranking is defined by who currently have the highest pvp_points
  Game pve_ranking is defined by who has the highest total_farm (gold + xp)
  Accounts ranking is defined by who has the highest season_points
  """
  def update_rankings! do
    Game.update_pvp_rankings!()
    Game.update_pve_ranking!()
    Accounts.update_ranking!()
  end

  def basic_attack, do: Game.basic_attack()

  def add_user_experience(user, experience), do: Accounts.add_user_experience(user, experience)

  def update_user!(user, updates), do: Accounts.update_user!(user, updates)

  def restarting?, do: is_nil(Game.current_match().last_server_update_at)

  def cached_items do
    match_id = if restarting?(), do: Game.last_match().id, else: Game.current_match().id

    case Cachex.get(:game_cache, "items-#{match_id}") do
      {:ok, nil} -> put_items_cache(match_id)
      {:ok, items} -> items
    end
  end

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

  defp put_items_cache(match_id) do
    items = Game.shop_list()
    Cachex.put(:game_cache, "items-#{match_id}", items)
    items
  end
end
