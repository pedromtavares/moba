defmodule Moba.Game do
  @moduledoc """
  Top-level domain of all gameplay logic, with cross-domain orchestration handled by Arena and Training
  """

  alias Moba.Game
  alias Game.{Arena, Avatars, Builds, Duels, Items, Heroes, Leagues, Matches, Quests, Skills, Skins, Targets, Training}

  # AVATARS

  defdelegate get_avatar!(avatar_id), to: Avatars

  defdelegate get_avatar_by_code!(code), to: Avatars

  defdelegate create_avatar!(avatar, attrs, match \\ nil), to: Avatars

  defdelegate list_avatars, to: Avatars

  defdelegate list_creation_avatars(codes \\ []), to: Avatars

  defdelegate list_unlockable_avatars, to: Avatars

  # BUILDS

  defdelegate generate_bot_build(attrs, avatar), to: Builds

  defdelegate skill_builds_for(role), to: Builds

  defdelegate skill_build_for(avatar, index), to: Builds

  # DUELS

  defdelegate auto_next_duel_phase!(duel), to: Arena

  defdelegate create_matchmaking!(user, opponent, auto), to: Arena

  defdelegate create_pvp_duel!(user, opponent), to: Arena

  defdelegate duel_challenge(user, opponent), to: Arena

  defdelegate finish_duel!(duel, winner, rewards), to: Arena

  defdelegate get_duel!(id), to: Duels

  defdelegate list_finished_duels(user), to: Duels

  defdelegate list_matchmaking(user), to: Duels

  defdelegate list_pvp_duels(user), to: Duels

  defdelegate next_duel_phase!(duel, hero \\ nil), to: Arena

  # HEROES

  defdelegate archive_hero!(hero), to: Training

  defdelegate broadcast_to_hero(hero_id), to: Training

  defdelegate buyback!(hero), to: Heroes

  defdelegate buyback_price(hero), to: Heroes

  defdelegate create_bot!(avatar, level, difficulty, tier, user), to: Heroes

  defdelegate create_hero!(attrs, user, avatar, skills), to: Training

  defdelegate finish_pve!(hero), to: Training

  defdelegate finalize_boss!(boss, boss_current_hp, hero), to: Training

  defdelegate finish_farming!(hero), to: Training

  defdelegate generate_boss!(hero), to: Training

  defdelegate get_hero!(hero_id), to: Heroes

  defdelegate latest_finished_heroes(user_id), to: Heroes

  defdelegate latest_unfinished_heroes(user_id), to: Heroes

  defdelegate level_cheat(hero), to: Heroes

  defdelegate list_all_finished_heroes(user_id), to: Heroes

  defdelegate list_all_unfinished_heroes(user_id), to: Heroes

  defdelegate list_pickable_heroes(user_id, duel_inserted_at), to: Heroes

  defdelegate master_league?(hero), to: Training

  defdelegate max_league?(hero), to: Training

  defdelegate maybe_finish_pve(hero), to: Training

  defdelegate maybe_generate_boss(hero), to: Training

  defdelegate prepare_league_challenge!(hero), to: Heroes

  defdelegate pve_ranking(limit \\ 20), to: Heroes

  defdelegate pve_search(hero), to: Heroes

  defdelegate refresh_targets!(hero), to: Training

  defdelegate set_skin!(hero, skin), to: Heroes

  defdelegate shard_buyback!(hero), to: Training

  defdelegate start_farming!(hero, state, turns), to: Heroes

  defdelegate subscribe_to_hero(hero_id), to: Training

  defdelegate update_attacker!(hero, updates), to: Training

  defdelegate update_hero!(hero, attrs, items \\ nil, skills \\ nil), to: Training

  defdelegate update_hero_collection!(hero), to: Training

  defdelegate update_pve_ranking!, to: Training

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

  defdelegate league_defender_for(attacker), to: Leagues

  defdelegate league_level_range_for(tier), to: Leagues

  defdelegate league_tier_for(level), to: Leagues

  defdelegate max_league_step_for(league), to: Leagues

  # MATCHES

  defdelegate create_match!(attrs), to: Matches

  defdelegate current_match, to: Matches

  defdelegate last_match, to: Matches

  defdelegate update_match!(match, attrs), to: Matches

  # QUESTS

  defdelegate active_quest_progression?(progressions), to: Quests

  defdelegate generate_daily_quest_progressions!(user_id \\ nil), to: Quests

  defdelegate last_completed_quest_progressions(hero), to: Quests

  defdelegate list_quest_progressions(user_id, code \\ nil), to: Quests

  defdelegate list_season_quest_progressions(user_id), to: Quests

  defdelegate list_daily_quest_progressions(user_id), to: Quests

  defdelegate track_pve_quests(hero), to: Quests

  # SKILLS

  defdelegate basic_attack, to: Skills

  defdelegate can_level_skill?(hero, skill), to: Skills

  defdelegate get_current_skills_from(skills), to: Skills

  defdelegate get_current_skill!(code, level \\ 1), to: Skills

  defdelegate get_skill!(skill_id), to: Skills

  defdelegate get_skill_by_code!(code, current, level \\ 1), to: Skills

  defdelegate level_up_skill!(hero, skill), to: Skills

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
end
