defmodule Moba.Game.Matches do
  @moduledoc """
  Manages Match records and queries.
  See Moba.Game.Schema.Match for more info.

  This is the starting point for the gameplay loop.
  """

  alias Moba.{Repo, Game, Accounts, Engine}
  alias Game.Schema.Match
  alias Game.Query.{ItemQuery, HeroQuery, AvatarQuery, SkillQuery}
  alias Accounts.Query.UserQuery
  import Ecto.Query, only: [from: 2]

  require Logger

  # -------------------------------- PUBLIC API

  @doc """
  The game's starting point. Creates all necessary resources and locks them against
  further edits in the admin panel. Also creates PVE and PVP bots.
  Matches last for 24h and will automatically be restarted by Moba.Game.Server
  """
  def start!(bot_level_range \\ 0..28) do
    end_active!()

    match =
      create!()
      |> generate_resources!()
      |> generate_hero_bots!(bot_level_range)
      |> generate_user_bots!()
      |> new_pvp_round!()
      |> server_update!()

    Moba.update_rankings!()
    Engine.read_all_battles()

    match
  end

  def current do
    Repo.all(from m in Match, where: m.active == true) |> List.first()
  end

  def last_active do
    Repo.all(from m in Match, where: m.active == false, order_by: [desc: m.id], limit: 1)
    |> List.first()
  end

  @doc """
  Right now only runs the automated bot battles and touches a datetime field
  so Moba.Game.Server knows when to run this again, currently every 10 mins.
  """
  def server_update!(match \\ current()) do
    skynet!()

    match
    |> update!(%{last_server_update_at: DateTime.utc_now()})
  end

  @doc """
  Each match has 2 PVP rounds that last 12 hours each. In each of these rounds, all heroes may
  battle each other exactly one time. Once a new round starts, all Heroes lose points, in an
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
    |> update!(%{last_pvp_round_at: DateTime.utc_now()})
  end

  def load_podium(%{winners: winners}) do
    [winners["1"], winners["2"], winners["3"]]
    |> Enum.map(fn hero_id ->
      Game.get_hero!(hero_id)
    end)
    |> Enum.reject(fn hero -> is_nil(hero) end)
  end

  def load_podium(_), do: nil

  # --------------------------------

  # Deactivates the current match and all pvp heroes, also assigning its winners and clearing all current heroes
  defp end_active! do
    active = current()

    if active do
      Game.update_ranking!()

      active
      |> update!(%{active: false})
      |> assign_and_award_winners!()
      |> clear_current_heroes!()
    end

    HeroQuery.pvp_active()
    |> Repo.update_all(set: [pvp_active: false, pvp_history: %{}])
  end

  defp create!(attrs \\ %{}) do
    Logger.info("Creating new match...")

    %Match{active: true}
    |> Match.changeset(attrs)
    |> Repo.insert!()
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

    AvatarQuery.base_current()
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

  # Generates a new PVP hero for every bot User with random avatars and levels
  defp generate_user_bots!(match) do
    Logger.info("Generating PVP bots...")

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
          4,
          user.pvp_points
        )

      Accounts.set_current_pvp_hero!(user, hero.id)
    end)

    match
  end

  defp update!(%Match{} = match, attrs) do
    match
    |> Match.changeset(attrs)
    |> Repo.update!()
  end

  # Awards winners and saves the top 10 heroes of the match
  defp assign_and_award_winners!(match) do
    top10 = Game.ranking(10)

    winners =
      Enum.reduce(top10, %{}, fn hero, acc ->
        unless hero.bot_difficulty, do: Accounts.award_medals_and_shards(hero.user, hero.pvp_ranking)
        Map.put(acc, hero.pvp_ranking, hero.id)
      end)

    update!(match, %{winners: winners})
  end

  # Clears all active heroes from the current players in the match
  # Users will need to create new Heroes for the Jungle and/or pick a new Hero for the Arena
  # Jungle heroes that haven't finished all of their available battles will not be cleared
  defp clear_current_heroes!(match) do
    Logger.info("Resetting players...")

    UserQuery.current_players()
    |> Repo.all()
    |> Repo.preload(:current_pve_hero)
    |> Enum.map(fn user ->
      base_changes = %{tutorial_step: 0, current_pvp_hero_id: nil}

      changes =
        if user.current_pve_hero && user.current_pve_hero.pve_battles_available == 0 do
          Map.put(base_changes, :current_pve_hero_id, nil)
        else
          base_changes
        end

      Accounts.update_user!(user, changes)
    end)

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
        _ -> 15..22
      end

    Enum.random(range)
  end
end
