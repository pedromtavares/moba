defmodule Moba.Constants do
  @moduledoc """
  Core game constants 
  """

  defmacro __using__(_) do
    quote do
      # General
      @base_hero_count 6
      @leagues %{
        0 => "Bronze League",
        1 => "Silver League",
        2 => "Gold League",
        3 => "Platinum League",
        4 => "Diamond League",
        5 => "Master League",
        6 => "Grandmaster League"
      }
      @pvp_tiers %{
        0 => "Herald",
        1 => "Herald Superior",
        2 => "Herald Elite",
        3 => "Guardian",
        4 => "Guardian Superior",
        5 => "Guardian Elite",
        6 => "Crusader",
        7 => "Crusader Superior",
        8 => "Crusader Elite",
        9 => "Archon",
        10 => "Supreme Archon",
        11 => "Ultimate Archon",
        12 => "Centurion",
        13 => "Gladiator",
        14 => "Champion",
        15 => "Legend",
        16 => "Ancient",
        17 => "Divine",
        18 => "Immortal"
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
      @current_ranking_date Timex.parse!("06-02-2022", "%d-%m-%Y", :strftime)
      @shard_buyback_minimum 5

      # PVE
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
      @max_total_farm 60_000
      @seconds_per_turn 2
      @max_pve_tier 7
      @pve_ranking_limit 200

      # League
      @platinum_league_tier 3
      @master_league_tier 5
      @max_league_tier 6
      @league_win_bonus 2000
      @boss_regeneration_multiplier 0.5
      @boss_win_bonus 2000

      # PVP
      @max_pvp_tier 18
      @match_timeout_in_hours 24
      @normal_matchmaking_shards 5
      @elite_matchmaking_shards 15
      @minimum_duel_points 2
      @maximum_points_difference 200
      @duel_timer_in_seconds 60
      @turn_timer_in_seconds 30
      @pvp_ranking_limit 50

      def base_hero_count, do: @base_hero_count
      def items_base_price, do: @items_base_price
      def normal_items_price, do: @items_base_price * 1
      def rare_items_price, do: @items_base_price * 3
      def epic_items_price, do: @items_base_price * 6
      def legendary_items_price, do: @items_base_price * 12
      def leagues, do: @leagues
      def pvp_tiers, do: @pvp_tiers
      def pve_tiers, do: @pve_tiers
      def turn_mp_regen_multiplier, do: @turn_mp_regen_multiplier
      def current_ranking_date, do: @current_ranking_date
      def shard_buyback_minimum, do: @shard_buyback_minimum

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
      def max_total_farm, do: @max_total_farm
      def seconds_per_turn, do: @seconds_per_turn
      def farm_per_turn(0), do: 800..1200
      def farm_per_turn(1), do: 850..1200
      def farm_per_turn(2), do: 900..1200
      def farm_per_turn(3), do: 950..1200
      def farm_per_turn(_), do: 1000..1200
      def pve_battle_rewards("weak", pve_tier) when pve_tier < @veteran_pve_tier, do: 500
      def pve_battle_rewards("moderate", pve_tier) when pve_tier < @veteran_pve_tier, do: 600
      def pve_battle_rewards("moderate", _), do: 500
      def pve_battle_rewards("strong", _), do: 600
      def max_pve_tier, do: @max_pve_tier
      def pve_ranking_limit, do: @pve_ranking_limit
      def refresh_targets_count(4), do: 5
      def refresh_targets_count(5), do: 10
      def refresh_targets_count(6), do: 15
      def refresh_targets_count(7), do: 20

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

      def max_pvp_tier, do: @max_pvp_tier
      def match_timeout_in_hours, do: @match_timeout_in_hours
      def normal_matchmaking_shards, do: @normal_matchmaking_shards
      def elite_matchmaking_shards, do: @elite_matchmaking_shards
      def maximum_points_difference, do: @maximum_points_difference
      def minimum_duel_points(points) when points < @minimum_duel_points, do: @minimum_duel_points
      def minimum_duel_points(points), do: points
      def victory_duel_points(diff) when diff < -@maximum_points_difference or diff > @maximum_points_difference, do: 0
      def victory_duel_points(diff) when diff > -40 and diff < 40, do: 5
      def victory_duel_points(diff) when diff < 0, do: ceil(150 / abs(diff)) |> minimum_duel_points()
      def victory_duel_points(diff), do: ceil(diff * 0.15)
      def defeat_duel_points(diff), do: victory_duel_points(-diff)
      def tie_duel_points(diff) when diff < -@maximum_points_difference or diff > @maximum_points_difference, do: 0
      def tie_duel_points(diff) when diff < 0, do: -(ceil(-diff * 0.05) |> minimum_duel_points())
      def tie_duel_points(diff), do: ceil(diff * 0.05) |> minimum_duel_points()
      def duel_timer_in_seconds, do: @duel_timer_in_seconds
      def turn_timer_in_seconds, do: @turn_timer_in_seconds
      def pvp_ranking_limit, do: @pvp_ranking_limit
    end
  end
end
