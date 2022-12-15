defmodule Moba.Conductor do
  @moduledoc """
  Module responsible for orchestrating the game's global tasks
  """

  alias Moba.{Game, Repo}
  alias Game.Query.{AvatarQuery, HeroQuery, ItemQuery, PlayerQuery, SkillQuery}

  require Logger

  @doc """
  Runs the auto matchmaking and touches a datetime field
  so Moba.Server knows when to run this again, currently every 30 mins.
  """
  def season_tick! do
    auto_matchmaking()
    Moba.update_pvp_ranking()
    Game.update_season_ranking!()

    Moba.current_season()
    |> Game.update_season!(%{last_server_update_at: DateTime.utc_now()})
  end

  def pvp_tick! do
    Game.update_pvp_ranking!(true)
    Repo.update_all(PlayerQuery.pvp_available(), set: [daily_matches: 0, daily_wins: 0])
    Game.update_season_ranking!()

    Moba.current_season()
    |> Game.update_season!(%{last_pvp_update_at: DateTime.utc_now()})
  end

  # Generates new resources based on canon so edits in the admin panel don't affect the current resources
  # also updating current records to current: false 
  def regenerate_resources! do
    resource_uuid = UUID.uuid1()
    Logger.info("Generating skills...")

    ids = SkillQuery.base_canon() |> Repo.all() |> duplicate_resources!(resource_uuid) |> Enum.map(& &1.id)
    Repo.update_all(SkillQuery.current() |> SkillQuery.exclude(ids), set: [current: false])

    Logger.info("Generating items...")

    ids = ItemQuery.base_canon() |> Repo.all() |> duplicate_resources!(resource_uuid) |> Enum.map(& &1.id)
    Repo.update_all(ItemQuery.current() |> ItemQuery.exclude(ids), set: [current: false])

    Logger.info("Generating avatars...")

    ids = AvatarQuery.base_canon() |> Repo.all() |> duplicate_avatars!(resource_uuid) |> Enum.map(& &1.id)
    Repo.update_all(AvatarQuery.current() |> AvatarQuery.exclude(ids), set: [current: false])

    # updates all existing hero-record relations to link to the newly created resources
    update_hero_skills()
    update_hero_items()
    update_hero_avatars()

    Game.update_season!(Moba.current_season(), %{resource_uuid: resource_uuid})
  end

  def regenerate_bots!(level_range \\ 0..35) do
    IO.puts("Generating new bots...")
    timestamp = Timex.now()

    AvatarQuery.base_canon()
    |> Repo.all()
    |> Enum.each(fn avatar ->
      Logger.info("Generating #{avatar.name}s...")

      Logger.info("Generating pvp bots...")

      Enum.each(1..10, fn _n ->
        create_bot_hero!(avatar, 24, "pvp_master", 5)
        create_bot_hero!(avatar, 26, "pvp_grandmaster", 6)
      end)

      Logger.info("Generating pve bots...")

      Enum.each(level_range, fn level ->
        create_bot_hero!(avatar, level, "weak")
        create_bot_hero!(avatar, level, "moderate")

        if level > 0 do
          create_bot_hero!(avatar, level, "strong")
          create_bot_hero!(avatar, level, "strong")
          create_bot_hero!(avatar, level, "strong")
        end
      end)
    end)

    archive_previous_bots!(HeroQuery.bots(), timestamp)

    Repo.delete_all(Game.Schema.Target)
  end

  # Archives all current bots so they can be removed later by Cleaner
  defp archive_previous_bots!(query, time) do
    query
    |> HeroQuery.created_before(time)
    |> HeroQuery.unarchived()
    |> Repo.update_all(set: [archived_at: DateTime.utc_now()])
  end

  defp auto_matchmaking do
    PlayerQuery.auto_matchmaking()
    |> Repo.all()
    |> Repo.preload(:user)
    |> Enum.map(fn player ->
      match = Game.auto_matchmaking!(player)

      if match do
        Game.get_match!(match.id) |> Game.continue_match!()
        Logger.info("Created match ##{match.id} for #{player.user.username}")
      end
    end)
  end

  defp create_bot_hero!(avatar, level, difficulty, league_tier \\ nil) do
    tier = league_tier || Game.league_tier_for(level)

    Game.create_bot!(avatar, level, difficulty, tier)
  end

  # by nilifing :id here we can make a perfect clone of a record
  defp duplicate_resources!(list, resource_uuid) do
    Enum.map(list, fn resource ->
      resource
      |> Map.put(:id, nil)
      |> Map.put(:resource_uuid, resource_uuid)
      |> Map.put(:current, true)
      |> Repo.insert!()
    end)
  end

  # because of intricasies of ultimates, we can't use the above function for Avatars
  defp duplicate_avatars!(list, resource_uuid) do
    Enum.map(list, fn avatar ->
      Game.create_avatar!(
        Map.merge(avatar, %{ultimate_id: nil, ultimate: nil, id: nil, current: true, resource_uuid: resource_uuid}),
        %{}
      )
    end)
  end

  defp update_hero_skills do
    Logger.info("Updating hero skills...")

    canon = SkillQuery.base_canon() |> Repo.all()
    all_current = SkillQuery.base_current() |> Repo.all()

    Enum.each(canon, fn skill ->
      current = Enum.find(all_current, &(&1.level == skill.level && &1.code == skill.code))

      if current do
        query = SkillQuery.non_current() |> SkillQuery.with_level(skill.level) |> SkillQuery.with_code(skill.code)
        skill_ids = Repo.all(query) |> Enum.map(& &1.id)
        query = SkillQuery.hero_skills_by_skill_ids(skill_ids)
        Repo.update_all(query, set: [skill_id: current.id])
      end
    end)
  end

  defp update_hero_items do
    Logger.info("Updating hero items...")

    canon = ItemQuery.base_canon() |> Repo.all()
    all_current = ItemQuery.base_current() |> Repo.all()

    Enum.each(canon, fn item ->
      current = Enum.find(all_current, &(&1.code == item.code))

      if current do
        query = ItemQuery.non_current() |> ItemQuery.with_code(item.code)
        item_ids = Repo.all(query) |> Enum.map(& &1.id)
        query = ItemQuery.hero_items_by_item_ids(item_ids)
        Repo.update_all(query, set: [item_id: current.id])
      end
    end)
  end

  defp update_hero_avatars do
    Logger.info("Updating hero avatars...")

    canon = AvatarQuery.base_canon() |> Repo.all()
    all_current = AvatarQuery.all_current() |> Repo.all()

    Enum.each(canon, fn avatar ->
      current = Enum.find(all_current, &(&1.code == avatar.code))

      if current do
        query = AvatarQuery.non_current() |> AvatarQuery.with_code(avatar.code)
        avatar_ids = Repo.all(query) |> Enum.map(& &1.id)
        query = HeroQuery.with_avatar_ids(Game.Schema.Hero, avatar_ids)
        Repo.update_all(query, set: [avatar_id: current.id])
      end
    end)
  end
end
