defmodule Moba.Game do
  @moduledoc """
  Top-level domain of all gameplay logic, with cross-domain orchestration handled by Arena and Training
  """

  alias Moba.Game.{
    Arena,
    Avatars,
    Builds,
    Duels,
    Items,
    Heroes,
    Leagues,
    Matches,
    Players,
    Quests,
    Seasons,
    Skills,
    Skins,
    Targets,
    Teams,
    Training
  }

  # AVATARS

  defdelegate avatar_stat_units, to: Avatars

  defdelegate get_avatar!(avatar_id), to: Avatars

  defdelegate get_avatar_by_code!(code), to: Avatars

  defdelegate create_avatar!(avatar, attrs), to: Avatars

  defdelegate list_all_current_avatars, to: Avatars

  defdelegate list_avatars, to: Avatars

  defdelegate list_creation_avatars(codes \\ []), to: Avatars

  defdelegate list_unlockable_avatars, to: Avatars

  # BUILDS

  defdelegate generate_bot_build(attrs, avatar), to: Builds

  defdelegate skill_builds_for(role), to: Builds

  defdelegate skill_build_for(avatar, index), to: Builds

  # DUELS

  defdelegate continue_duel!(duel, hero \\ nil), to: Arena

  defdelegate create_duel!(player, opponent), to: Arena

  defdelegate duel_challenge(player, opponent), to: Arena

  defdelegate get_duel!(id), to: Duels

  defdelegate list_finished_duels(player), to: Duels

  defdelegate list_duels(player), to: Duels

  # HEROES

  defdelegate archive_hero!(hero), to: Training

  defdelegate available_hero?(hero), to: Heroes

  defdelegate available_pvp_heroes(player, excluded_hero_ids), to: Heroes

  defdelegate available_top_heroes, to: Heroes

  defdelegate broadcast_to_hero(hero_id), to: Training

  defdelegate buyback!(hero), to: Heroes

  defdelegate buyback_price(hero), to: Heroes

  defdelegate can_shard_buyback?(hero), to: Heroes

  defdelegate create_bot!(avatar, level, difficulty, tier), to: Heroes

  defdelegate create_current_pve_hero!(attrs, player, avatar, skills), to: Training

  defdelegate create_hero!(attrs, player, avatar, skills), to: Training

  defdelegate finish_pve!(hero), to: Training

  defdelegate finalize_boss!(boss, boss_current_hp, hero), to: Training

  defdelegate finalize_league_attacker!(attacker, winner), to: Training

  defdelegate finalize_pve_attacker!(attacker, defender, winner, rewards), to: Training

  defdelegate finish_farming!(hero), to: Training

  defdelegate generate_boss!(hero), to: Training

  defdelegate get_hero!(hero_id), to: Heroes

  defdelegate get_heroes(hero_ids), to: Heroes

  defdelegate latest_finished_heroes(player_id), to: Heroes

  defdelegate latest_unfinished_heroes(player_id), to: Heroes

  defdelegate level_cheat(hero), to: Heroes

  defdelegate list_all_finished_heroes(player_id), to: Heroes

  defdelegate list_all_unfinished_heroes(player_id), to: Heroes

  defdelegate master_league?(hero), to: Training

  defdelegate max_league?(hero), to: Training

  defdelegate maybe_finish_pve(hero), to: Training

  defdelegate pve_ranking(limit \\ 20), to: Heroes

  defdelegate rank_finished_heroes!, to: Training

  defdelegate refresh_targets!(hero), to: Training

  defdelegate set_skin!(hero, skin), to: Heroes

  defdelegate shard_buyback!(hero), to: Heroes

  defdelegate start_farming!(hero, state, turns), to: Heroes

  defdelegate start_league_battle!(hero), to: Training

  defdelegate subscribe_to_hero(hero_id), to: Training

  defdelegate trained_pvp_heroes(player_id, excluded_hero_ids, limit), to: Heroes

  defdelegate update_attacker!(hero, updates), to: Training

  defdelegate update_hero!(hero, attrs, items \\ nil, skills \\ nil), to: Training

  defdelegate update_hero_collection!(hero), to: Training

  defdelegate xp_to_next_hero_level(level), to: Heroes

  # ITEMS

  defdelegate buy_item!(hero, item), to: Items

  defdelegate can_equip_item?(hero, item), to: Items

  defdelegate can_buy_item?(hero, item), to: Items

  defdelegate get_item!(item_id), to: Items

  defdelegate get_item_by_code!(code), to: Items

  defdelegate item_ingredients_count(item), to: Items

  defdelegate item_price(item), to: Items

  defdelegate item_sell_price(hero, item), to: Items

  defdelegate previous_item_rarity(item), to: Items

  defdelegate sell_item!(hero, item), to: Items

  defdelegate shop_list, to: Items

  defdelegate sort_items(list), to: Items

  defdelegate transmute_item!(hero, recipe, item), to: Items

  # LEAGUES

  defdelegate league_level_range_for(tier), to: Leagues

  defdelegate league_tier_for(level), to: Leagues

  defdelegate max_league_step_for(league), to: Leagues

  # MATCHES

  defdelegate auto_matchmaking!(player), to: Arena

  defdelegate continue_match!(match, player_picks), to: Arena

  defdelegate continue_match!(match), to: Arena

  defdelegate get_match!(id), to: Matches

  defdelegate latest_manual_match(player), to: Matches

  defdelegate list_matches(player), to: Matches

  defdelegate manual_matchmaking!(player), to: Arena

  defdelegate reset_match!(match), to: Arena

  # PLAYERS

  defdelegate bot_ranking, to: Players

  defdelegate create_player!(attrs), to: Players

  defdelegate daily_ranking(limit), to: Players

  defdelegate duel_opponents(player, online_ids), to: Players

  defdelegate get_player!(id), to: Players

  defdelegate get_player_from_user!(user_id), to: Players

  defdelegate season_ranking(limit), to: Players

  defdelegate set_player_available!(player), to: Players

  defdelegate set_player_unavailable!(player), to: Players

  defdelegate set_current_pve_hero!(player, hero_id), to: Players

  defdelegate update_collection!(player, hero_collection), to: Players

  defdelegate update_player!(player, attrs), to: Players

  defdelegate update_preferences!(player, preferences), to: Players

  defdelegate update_daily_ranking!(update_tiers? \\ false), to: Arena

  defdelegate update_season_ranking!, to: Players

  defdelegate update_tutorial_step!(player, step), to: Players

  # QUESTS

  defdelegate get_quest(tier), to: Quests

  defdelegate last_completed_quest(hero), to: Quests

  # SEASONS

  defdelegate current_season, to: Seasons

  defdelegate update_season!(season, attrs), to: Seasons

  # SKILLS

  defdelegate basic_attack, to: Skills

  defdelegate can_level_skill?(hero, skill), to: Skills

  defdelegate get_current_skills_from(skills), to: Skills

  defdelegate get_current_skill!(code, level \\ 1), to: Skills

  defdelegate get_skill!(skill_id), to: Skills

  defdelegate get_skill_by_code!(code, current, level \\ 1), to: Skills

  defdelegate level_up_skill!(hero, skill), to: Skills

  defdelegate list_all_current_skills, to: Skills

  defdelegate list_chosen_skills(skill_ids), to: Skills

  defdelegate list_creation_skills(level, codes \\ []), to: Skills

  defdelegate list_normal_skills, to: Skills

  defdelegate list_ultimate_skills, to: Skills

  defdelegate list_unlockable_skills, to: Skills

  defdelegate max_leveled_skills(skills), to: Skills

  defdelegate max_skill_level(skill), to: Skills

  # SKINS

  defdelegate default_skin(avatar_code), to: Skins

  defdelegate get_skin_by_code!(code), to: Skins

  defdelegate list_avatar_skins(avatar_code), to: Skins

  defdelegate list_skins_with_codes(codes), to: Skins

  # TARGETS

  defdelegate generate_targets!(hero), to: Training

  defdelegate get_target!(target_id), to: Targets

  defdelegate list_targets(hero), to: Targets

  defdelegate start_pve_battle!(target), to: Training

  # TEAMS

  defdelegate create_team!(attrs), to: Teams

  defdelegate delete_team!(team), to: Teams

  defdelegate list_teams(player), to: Teams

  defdelegate update_team!(team, attrs), to: Teams
end
