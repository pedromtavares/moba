defmodule Moba do
  @moduledoc """
  High-level helpers, core variables and cross-context orchestration
  """

  alias Moba.{Game, Accounts, Conductor, Cleaner}

  # General constants
  @initial_battles 30
  @battles_per_tier 5
  @initial_gold 800
  @veteran_initial_gold 2000
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
  @easy_mode_max_farm 24_000
  @turn_mp_regen_multiplier 0.01
  @final_tutorial_step 14

  # PVE constants
  @base_xp 600
  @xp_increment 50
  @battle_xp 150
  @total_pve_turns 25
  @buyback_multiplier 20
  @veteran_buyback_multiplier 10
  @refresh_targets_count 5
  @maximum_total_farm 30_000
  @seconds_per_turn 5
  @xp_farm_per_turn 1000..1200
  @gold_farm_per_turn 800..1000

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
  @league_win_bonus 2000
  @league_buff_multiplier 0.4
  @boss_regeneration_multiplier 0.5
  @boss_win_bonus 2000

  def initial_battles, do: @initial_battles
  def battles_per_tier, do: @battles_per_tier
  def initial_gold(%{pve_tier: tier}) when tier > 0, do: @veteran_initial_gold
  def initial_gold(_), do: @initial_gold
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
  def easy_mode_max_farm, do: @easy_mode_max_farm
  def turn_mp_regen_multiplier, do: @turn_mp_regen_multiplier
  def final_tutorial_step, do: @final_tutorial_step

  def base_xp, do: @base_xp
  def xp_increment, do: @xp_increment
  def battle_xp, do: @battle_xp
  def total_pve_turns, do: @total_pve_turns
  def buyback_multiplier(%{pve_tier: tier}) when tier > 1, do: @veteran_buyback_multiplier
  def buyback_multiplier(_), do: @buyback_multiplier
  def refresh_targets_count, do: @refresh_targets_count
  def maximum_total_farm, do: @maximum_total_farm
  def seconds_per_turn, do: @seconds_per_turn
  def xp_farm_per_turn, do: @xp_farm_per_turn
  def gold_farm_per_turn, do: @gold_farm_per_turn

  def pvp_heroes_per_page, do: @pvp_heroes_per_page
  def ranking_heroes_per_page, do: @ranking_heroes_per_page
  def pvp_timeout_in_hours, do: @pvp_timeout_in_hours
  def pvp_round_decay, do: @pvp_round_decay
  def pvp_round_timeout_in_hours, do: @pvp_round_timeout_in_hours
  def season_points_per_medal, do: @season_points_per_medal
  def max_season_tier, do: @max_season_tier

  def master_league_tier, do: @master_league_tier
  def max_league_tier, do: @max_league_tier
  def league_win_bonus, do: @league_win_bonus
  def league_buff_multiplier, do: @league_buff_multiplier
  def boss_regeneration_multiplier, do: @boss_regeneration_multiplier
  def boss_win_bonus, do: @boss_win_bonus

  def xp_percentage("weak", _), do: 100
  def xp_percentage("moderate", false), do: 100
  def xp_percentage("moderate", true), do: 200
  def xp_percentage("strong", _), do: 200

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
  Game pve_ranking is defined by who has the highest total_farm (gold)
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
