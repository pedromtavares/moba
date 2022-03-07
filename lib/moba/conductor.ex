defmodule Moba.Conductor do
  @moduledoc """
  Server responsible for orchestrating the main gameplay loop
  """
  use GenServer

  alias Moba.{Repo, Game, Accounts, Engine}
  alias Game.Query.{ItemQuery, HeroQuery, AvatarQuery, SkillQuery}
  alias Accounts.Query.UserQuery

  require Logger

  # 30 secs
  @check_timeout 1000 * 30

  # 10mins
  @update_diff_in_seconds 60 * 10

  # 1 day
  @reset_diff_in_seconds 60 * 60 * 24

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def init(state) do
    schedule_check()
    {:ok, state}
  end

  def schedule_check, do: Process.send_after(self(), :server_check, @check_timeout)

  def handle_info(:server_check, state) do
    schedule_check()

    match = Moba.current_match()

    if time_diff_in_seconds(match.inserted_at) >= @reset_diff_in_seconds do
      Moba.start!()
    end

    if time_diff_in_seconds(match.last_server_update_at) >= @update_diff_in_seconds do
      server_update!(match)
    end

    {:noreply, state}
  end

  @doc """
  The game's starting point. Also creates PVP bots and generates new resources
  Matches last for 24h and will automatically be restarted by Moba.Game.Server
  """
  def start_match! do
    end_active_match!()

    match =
      create_match!()
      |> server_update!()

    Game.generate_daily_quest_progressions!()
    Accounts.update_ranking!()

    match
  end

  @doc """
  Right now only runs the automated bot battles and touches a datetime field
  so Moba.Game.Server knows when to run this again, currently every 10 mins.
  """
  def server_update!(match \\ Moba.current_match()) do
    # skynet(match)
    Accounts.update_ranking!()

    match
    |> Game.update_match!(%{last_server_update_at: DateTime.utc_now()})
  end

  @doc """
  Creates all necessary resources and locks them against
  further edits in the admin panel. Also creates PVE bots.
  """
  def regenerate_resources! do
    Game.current_match() |> generate_resources!()
  end

  def regenerate_pve_bots!(level_range) do
    timestamp = Timex.now()

    AvatarQuery.base_canon()
    |> Repo.all()
    |> Enum.each(fn avatar ->
      Logger.info("Generating #{avatar.name}s...")

      Enum.each(level_range, fn level ->
        Game.create_bot_hero!(avatar, level, "weak")
        Game.create_bot_hero!(avatar, level, "moderate")

        if level > 0 do
          Game.create_bot_hero!(avatar, level, "strong")
          Game.create_bot_hero!(avatar, level, "strong")
          Game.create_bot_hero!(avatar, level, "strong")
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
        |> Enum.map(&Game.create_pvp_bot_hero!(user, &1))
      end)

    archive_previous_bots!(HeroQuery.pvp_bots(), timestamp)

    bot_heroes
    |> List.flatten()
    |> Enum.map(&Game.update_hero_collection!(&1))
  end

  # Deactivates the current match and all pvp heroes, also assigning its winners and clearing all current heroes
  defp end_active_match! do
    active = Moba.current_match()

    if active, do: Game.update_match!(active, %{active: false})
  end

  defp create_match!(attrs \\ %{}) do
    Logger.info("Creating new match...")
    Game.create_match!(attrs)
  end

  # Generates new resources based on canon so edits in the admin panel doesn't affect the current match (only the next)
  defp generate_resources!(match) do
    Logger.info("Generating resources...")

    Logger.info("Generating skills...")

    ids = SkillQuery.base_canon() |> Repo.all() |> duplicate_resources!(match) |> Enum.map(& &1.id)
    Repo.update_all(SkillQuery.current() |> SkillQuery.exclude(ids), set: [current: false])

    Logger.info("Generating items...")

    ids = ItemQuery.base_canon() |> Repo.all() |> duplicate_resources!(match) |> Enum.map(& &1.id)
    Repo.update_all(ItemQuery.current() |> ItemQuery.exclude(ids), set: [current: false])

    Logger.info("Generating avatars...")

    ids = AvatarQuery.base_canon() |> Repo.all() |> duplicate_avatars!(match) |> Enum.map(& &1.id)
    Repo.update_all(AvatarQuery.current() |> AvatarQuery.exclude(ids), set: [current: false])

    Logger.info("Updating build skills...")
    update_build_skills()
    Logger.info("Updating hero items...")
    update_hero_items()
    Logger.info("Updating hero avatars...")
    update_hero_avatars()

    match
  end

  # Archives all current bots so they can be removed later by Cleaner
  defp archive_previous_bots!(query, time) do
    query
    |> HeroQuery.created_before(time)
    |> HeroQuery.unarchived()
    |> Repo.update_all(set: [archived_at: DateTime.utc_now()])
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

  defp time_diff_in_seconds(nil), do: 0
  defp time_diff_in_seconds(field), do: Timex.diff(Timex.now(), field, :seconds)

  defp update_build_skills do
    canon = SkillQuery.base_canon() |> Repo.all()
    all_current = SkillQuery.base_current() |> Repo.all()

    Enum.each(canon, fn skill ->
      current = Enum.find(all_current, &(&1.level == skill.level && &1.code == skill.code))

      if current do
        query = SkillQuery.non_current() |> SkillQuery.with_level(skill.level) |> SkillQuery.with_code(skill.code)
        skill_ids = Repo.all(query) |> Enum.map(& &1.id)
        query = SkillQuery.build_skills_by_skill_ids(skill_ids)
        Repo.update_all(query, set: [skill_id: current.id])
      end
    end)
  end

  defp update_hero_items do
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

  defp skynet(%{last_server_update_at: time}) do
    Enum.each(1..5, fn _n ->
      bot = UserQuery.skynet_bot(time) |> Repo.all() |> List.first()

      if bot do
        duel = Moba.normal_matchmaking!(bot)

        if duel do
          Logger.info("Created duel ##{duel.id} for #{bot.username}")
          Game.get_duel!(duel.id) |> Game.next_duel_phase!(skynet_hero(bot, duel))
          Engine.first_duel_battle(duel) |> Engine.auto_finish_battle!()
          Game.get_duel!(duel.id) |> Game.next_duel_phase!(skynet_hero(bot, duel))
          Engine.last_duel_battle(duel) |> Engine.auto_finish_battle!()

          later = Timex.shift(time, minutes: 190)
          Accounts.update_user!(bot, %{last_online_at: later})
        end
      end
    end)
  end

  defp skynet_hero(bot, duel) do
    Game.eligible_heroes_for_pvp(bot.id, duel.inserted_at) |> List.first()
  end
end
