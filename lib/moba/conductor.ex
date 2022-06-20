defmodule Moba.Conductor do
  @moduledoc """
  Module responsible for orchestrating the game's global tasks
  """

  alias Moba.{Repo, Game, Accounts}
  alias Game.Query.{ItemQuery, HeroQuery, AvatarQuery, SkillQuery}
  alias Accounts.Query.UserQuery

  require Logger

  @doc """
  Runs the automated bot battles and touches a datetime field
  so Moba.Server knows when to run this again, currently every 10 mins.
  """
  def server_update!(match \\ Moba.current_match()) do
    auto_matchmaking_bots(match)
    auto_matchmaking_users()
    Accounts.update_ranking!()

    Game.update_match!(match, %{last_server_update_at: DateTime.utc_now()})
  end

  def start_match! do
    current = Moba.current_match()

    if current, do: Game.update_match!(current, %{active: false})

    match = Game.create_match!(%{}) |> server_update!()

    Game.generate_daily_quest_progressions!()
    Accounts.update_ranking!()

    match
  end

  # Generates new resources based on canon so edits in the admin panel don't affect the current match (only the next)
  # also updating current records to current: false 
  def regenerate_resources! do
    match = Game.current_match()

    Logger.info("Generating skills...")

    ids = SkillQuery.base_canon() |> Repo.all() |> duplicate_resources!(match) |> Enum.map(& &1.id)
    Repo.update_all(SkillQuery.current() |> SkillQuery.exclude(ids), set: [current: false])

    Logger.info("Generating items...")

    ids = ItemQuery.base_canon() |> Repo.all() |> duplicate_resources!(match) |> Enum.map(& &1.id)
    Repo.update_all(ItemQuery.current() |> ItemQuery.exclude(ids), set: [current: false])

    Logger.info("Generating avatars...")

    ids = AvatarQuery.base_canon() |> Repo.all() |> duplicate_avatars!(match) |> Enum.map(& &1.id)
    Repo.update_all(AvatarQuery.current() |> AvatarQuery.exclude(ids), set: [current: false])

    # updates all existing hero-record relations to link to the newly created resources
    update_hero_skills()
    update_hero_items()
    update_hero_avatars()

    match
  end

  def regenerate_pve_bots!(level_range) do
    timestamp = Timex.now()

    AvatarQuery.base_canon()
    |> Repo.all()
    |> Enum.each(fn avatar ->
      Logger.info("Generating #{avatar.name}s...")

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

    archive_previous_bots!(HeroQuery.pve_bots(), timestamp)

    Repo.delete_all(Game.Schema.Target)
  end

  def regenerate_pvp_bots! do
    timestamp = Timex.now()

    all_avatars = AvatarQuery.base_canon() |> Repo.all()

    bot_heroes =
      UserQuery.eligible_arena_bots()
      |> Repo.all()
      |> Enum.map(fn user ->
        Logger.info("New PVP heroes for #{user.username}: #{user.bot_codes |> Enum.join(", ")}")

        user.bot_codes
        |> Enum.map(fn code -> Enum.find(all_avatars, &(&1.code == code)) end)
        |> Enum.filter(& &1)
        |> Enum.map(&create_pvp_bot_hero!(user, &1))
      end)

    archive_previous_bots!(HeroQuery.pvp_bots(), timestamp)

    bot_heroes
    |> List.flatten()
    |> Enum.map(&Game.update_hero_collection!(&1))
  end

  # Archives all current bots so they can be removed later by Cleaner
  defp archive_previous_bots!(query, time) do
    query
    |> HeroQuery.created_before(time)
    |> HeroQuery.unarchived()
    |> Repo.update_all(set: [archived_at: DateTime.utc_now()])
  end

  defp auto_matchmaking_bots(%{last_server_update_at: updated_at, inserted_at: inserted_at}) do
    time = updated_at || inserted_at

    Enum.each(1..2, fn _n ->
      bot = UserQuery.skynet_bot(time) |> Repo.all() |> List.first()

      if bot do
        duel = Moba.bot_matchmaking!(bot)

        if duel do
          Logger.info("Created duel ##{duel.id} for #{bot.username}")
          later = Timex.shift(time, minutes: 190)
          Accounts.update_user!(bot, %{last_online_at: later})
        end
      end
    end)
  end

  defp auto_matchmaking_users do
    Enum.each(1..2, fn _n ->
      user = UserQuery.auto_matchmaking() |> Repo.all() |> List.first()

      if user do
        duel = Moba.auto_matchmaking!(user)

        if duel do
          Logger.info("Created duel ##{duel.id} for #{user.username}")
        end
      end
    end)
  end

  defp create_bot_hero!(avatar, level, difficulty, league_tier \\ nil, user \\ nil) do
    tier = league_tier || Game.league_tier_for(level)

    Game.create_bot!(avatar, level, difficulty, tier, user)
  end

  defp create_pvp_bot_hero!(%{bot_tier: tier} = user, avatar) do
    level = Game.league_level_range_for(tier) |> Enum.random()

    difficulty =
      cond do
        tier == Moba.master_league_tier() -> "pvp_master"
        tier == Moba.max_league_tier() -> "pvp_grandmaster"
        true -> "strong"
      end

    create_bot_hero!(avatar, level, difficulty, tier, user)
  end

  # by nilifing :id here we can make a perfect clone of a record
  defp duplicate_resources!(list, match) do
    Enum.map(list, fn resource ->
      resource
      |> Repo.preload(:match)
      |> Map.put(:id, nil)
      |> Map.put(:current, true)
      |> Map.put(:match_id, match.id)
      |> Repo.insert!()
    end)
  end

  # because of intricasies of ultimates, we can't use the above function for Avatars
  defp duplicate_avatars!(list, match) do
    Enum.map(list, fn avatar ->
      Game.create_avatar!(
        Map.merge(avatar, %{ultimate_id: nil, match_id: nil, match: nil, ultimate: nil, id: nil, current: true}),
        %{},
        match
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
