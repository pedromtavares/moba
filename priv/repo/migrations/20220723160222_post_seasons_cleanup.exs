defmodule Moba.Repo.Migrations.PostSeasonsCleanup do
  use Ecto.Migration

  def up do
    alter table(:users) do
      remove :is_bot
      remove :is_guest
      remove :experience
      remove :level
      remove :tutorial_step
      remove :status
      remove :ranking
      remove :duel_score
      remove :duel_wins
      remove :duel_count
      remove :medal_count
      remove :hero_collection
      remove :season_tier
      remove :season_points
      remove :bot_codes
      remove :bot_tier
      remove :shard_limit
      remove :pve_tier
      remove :unread_messages_count
      remove :match_history
      remove :last_challenge_at
      remove :preferences
      remove :current_pve_hero_id
      remove :current_pvp_hero_id
      remove :title_quest_id
    end

    alter table(:battles) do
      remove :match_id
    end

    alter table(:skills) do
      remove :match_id
    end

    alter table(:items) do
      remove :match_id
    end

    alter table(:avatars) do
      remove :match_id
    end

    alter table(:heroes) do
      remove :match_id
      remove :user_id
    end

    alter table(:duels) do
      remove :user_id
      remove :opponent_id
      remove :winner_id
    end

    drop table(:matches)
    drop table(:quest_progressions)
    drop table(:quests)
  end
end
