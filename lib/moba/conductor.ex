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

  # 12 hours
  @new_round_diff_in_seconds 60 * 60 * Moba.pvp_round_timeout_in_hours()

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

    if time_diff_in_seconds(match.last_pvp_round_at) >= @new_round_diff_in_seconds do
      new_pvp_round!(match)
    end

    {:noreply, state}
  end

  @doc """
  The game's starting point. Creates all necessary resources and locks them against
  further edits in the admin panel. Also creates PVE and PVP bots.
  Matches last for 24h and will automatically be restarted by Moba.Game.Server
  """
  def start_match!(bot_level_range \\ 0..28) do
    end_active_match!()

    match =
      create_match!()
      |> generate_resources!()
      |> generate_hero_bots!(bot_level_range)
      |> refresh_targets!()
      |> generate_user_bots!()
      |> new_pvp_round!()
      |> server_update!()

    Accounts.update_ranking!()
    Engine.read_all_battles()

    match
  end

  @doc """
  Right now only runs the automated bot battles and touches a datetime field
  so Moba.Game.Server knows when to run this again, currently every 10 mins.
  """
  def server_update!(match \\ Moba.current_match()) do
    skynet!()

    Game.update_pvp_ranking!()
    Game.update_pve_ranking!()

    match
    |> Game.update_match!(%{last_server_update_at: DateTime.utc_now()})
  end

  @doc """
  Each match has 2 PVP rounds that last 12 hours each. In each of these rounds, all heroes may
  battle each other exactly one time. Once a new round starts, all Users lose points, in an
  effort to avoid having users purposefully not play a round in order to not lose points.
  New PVP rounds will be started automatically by Moba.Game.Server
  """
  def new_pvp_round!(match) do
    HeroQuery.pvp_active()
    |> Repo.update_all(set: [pvp_history: %{}])

    UserQuery.with_pvp_points()
    |> Repo.all()
    |> Enum.map(fn user -> Accounts.user_pvp_decay!(user) end)

    match
    |> Game.update_match!(%{last_pvp_round_at: DateTime.utc_now()})
  end

  # Deactivates the current match and all pvp heroes, also assigning its winners and clearing all current heroes
  defp end_active_match! do
    active = Moba.current_match()

    if active do
      Game.update_pvp_ranking!()

      active
      |> Game.update_match!(%{active: false})
      |> assign_and_award_winners!()
      |> clear_current_heroes!()
    end

    HeroQuery.pvp_active()
    |> Repo.update_all(set: [pvp_active: false, pvp_history: %{}])
  end

  defp create_match!(attrs \\ %{}) do
    Logger.info("Creating new match...")
    Game.create_match!(attrs)
  end

  # generates match-specific resources so edits in admin panel wont affect current match
  defp generate_resources!(match) do
    Logger.info("Generating resources...")

    SkillQuery.base_canon() |> Repo.all() |> duplicate_resources!(match)
    ItemQuery.base_canon() |> Repo.all() |> duplicate_resources!(match)
    AvatarQuery.base_canon() |> Repo.all() |> duplicate_avatars!(match)

    match
  end

  # generates PVE bots for every eligible Avatar, every difficulty and every level in the range provided
  defp generate_hero_bots!(match, level_range) do
    Logger.info("Generating PVE bots...")

    AvatarQuery.all_current()
    |> Repo.all()
    |> Enum.each(fn avatar ->
      Logger.info("Generating #{avatar.name}s...")

      Enum.each(level_range, fn level ->
        Game.create_bot_hero!(avatar, level, "weak", match)
        Game.create_bot_hero!(avatar, level, "moderate", match)
        Game.create_bot_hero!(avatar, level, "strong", match)
      end)
    end)

    match
  end

  # generates new targets for unfinished Jungle heroes
  defp refresh_targets!(match) do
    UserQuery.current_players()
    |> Repo.all()
    |> Repo.preload(:current_pve_hero)
    |> Enum.map(fn %{current_pve_hero: hero} = user ->
      Game.generate_targets!(%{hero | user: user})
    end)

    match
  end

  # Generates a new PVP hero for every bot User with random avatars and levels
  defp generate_user_bots!(match) do
    Logger.info("Generating PVP bots...")

    HeroQuery.bots() |> HeroQuery.unarchived() |> Repo.update_all(set: [archived_at: DateTime.utc_now()])

    avatars = AvatarQuery.all_current() |> Repo.all()

    UserQuery.eligible_arena_bots()
    |> Repo.all()
    |> Enum.map(fn user ->
      Logger.info("New PVP hero for #{user.username}")

      avatar = Enum.random(avatars)
      difficulty = Application.get_env(:moba, :arena_difficulty)
      level = arena_bot_level(difficulty)

      hero =
        Game.create_bot_hero!(
          avatar,
          level,
          "strong",
          match,
          user,
          user.pvp_points
        )

      Accounts.set_current_pvp_hero!(user, hero.id)
    end)

    match
  end

  # Awards winners and saves the PVP top 10 heroes of the match
  defp assign_and_award_winners!(match) do
    top10 = Game.pvp_ranking(10)

    winners =
      Enum.reduce(top10, %{}, fn hero, acc ->
        unless hero.bot_difficulty, do: Accounts.award_medals_and_shards(hero.user, hero.pvp_ranking)
        Map.put(acc, hero.pvp_ranking, hero.id)
      end)

    Game.update_match!(match, %{winners: winners})
  end

  # Clears all active heroes from the current players in the match
  # Users will need to create new Heroes for the Jungle and/or pick a new Hero for the Arena
  defp clear_current_heroes!(match) do
    Logger.info("Clearing active players...")
    Accounts.clear_active_players!()
    match
  end

  # Picks one PVP bot to battle someone in the Arena. Over the period of a PVP round, bots should attempt to battle
  # each Hero twice (although only the first will be allowed), considering the current max bot number of 30
  # We use the pvp_last_picked field here to tell skynet that this bot shouldn't be picked to battle again for another 6 hours
  defp skynet! do
    now = Timex.now()
    attacker = HeroQuery.skynet_bot(now) |> Repo.all() |> List.first()

    if attacker do
      HeroQuery.with_pvp_points()
      |> Repo.all()
      |> Enum.each(fn defender ->
        defender &&
          %{attacker: Game.get_hero!(attacker.id), defender: Game.get_hero!(defender.id)}
          |> Engine.create_pvp_battle!()
          |> Engine.auto_finish_battle!()
      end)

      Game.update_hero!(attacker, %{pvp_last_picked: now |> Timex.shift(hours: +6)})
    end
  end

  # by nilifing :id here we can make a perfect clone of a record
  defp duplicate_resources!(list, match) do
    Enum.map(list, fn resource ->
      resource
      |> Repo.preload(:match)
      |> Map.put(:id, nil)
      |> Map.put(:match_id, match.id)
      |> Repo.insert!()
    end)
  end

  # because of intricasies of ultimates, we can't use the above function for Avatars
  defp duplicate_avatars!(list, match) do
    Enum.each(list, fn avatar ->
      Game.create_avatar!(
        Map.merge(avatar, %{ultimate_id: nil, match_id: nil, match: nil, ultimate: nil, id: nil}),
        %{},
        match
      )
    end)
  end

  defp arena_bot_level(difficulty) do
    range =
      case difficulty do
        "moderate" -> 18..25
        "strong" -> 22..25
        "ultimate" -> 25..25
        _ -> 15..22
      end

    Enum.random(range)
  end

  defp time_diff_in_seconds(nil), do: 0
  defp time_diff_in_seconds(field), do: Timex.diff(Timex.now(), field, :seconds)
end
