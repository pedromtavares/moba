defmodule Moba.Accounts.Users do
  @moduledoc """
  Manages User records and progression via levels, shards and medals.

  Also includes logic for user-related PVP handling, which should be
  extracted to the Game context at some point (Player entity perhaps?).
  """

  alias Moba.{Repo, Accounts}
  alias Accounts.Schema.User
  alias Accounts.Query.UserQuery

  # -------------------------------- PUBLIC API

  def get!(nil), do: nil
  def get!(id), do: Repo.get!(UserQuery.load(), id)

  def get_with_unlocks!(id), do: get!(id) |> Repo.preload(:unlocks)

  def get_with_current_heroes!(id), do: get!(id) |> Repo.preload(current_pve_hero: :avatar, current_pvp_hero: :avatar)

  def get_by_username(username), do: Repo.get_by(UserQuery.load(), username: username)

  def create(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  def update!(%User{} = user, attrs) do
    user
    |> User.update_changeset(attrs)
    |> Repo.update!()
  end

  def update_tutorial_step!(user, step), do: update!(user, %{tutorial_step: step})

  def set_online_now(user) do
    UserQuery.by_user(User, user)
    |> Repo.update_all(set: [last_online_at: DateTime.utc_now()])
  end

  def duel_list(user) do
    UserQuery.online_users()
    |> UserQuery.with_status("available")
    |> UserQuery.exclude_user(user)
    |> Repo.all()
  end

  @doc """
  Users gain experience from PVE battles (along with their Hero)
  When they level up, they increment their shard_count, which can be used for Unlocks
  """
  def add_experience(user, experience) do
    user
    |> User.experience_changeset(%{experience: experience + user.experience})
    |> check_if_leveled()
    |> Repo.update!()
  end

  @doc """
  Given to the top 3 of the Arena when the match ends
  Medals are displayed on the Arena and Shards are used for unlocking new content
  """
  def award_medals_and_shards(user, ranking, league_tier) when ranking > 0 and ranking < 4 do
    {medals, shards} =
      case ranking do
        1 -> {3, 200}
        2 -> {2, 150}
        3 -> {1, 100}
      end

    shards = if league_tier == Moba.master_league_tier(), do: div(shards, 2), else: shards

    total_medals = if league_tier == Moba.max_league_tier(), do: user.medal_count + medals, else: user.medal_count
    total_shards = user.shard_count + shards

    update!(user, %{medal_count: total_medals, shard_count: total_shards})
  end

  def award_medals_and_shards(user, _, _), do: user

  @doc """
  Guests are used after a Hero is created from the homepage, so the user
  can experiment the game without the inconvenience of creating an account
  They eventually can register and all data is transferred to the new account
  """
  def create_guest(conn) do
    uuid = UUID.uuid1()
    name = String.slice(uuid, 0..14)
    email = "#{name}@guest.com"
    pass = Faker.String.base64()

    case Pow.Plug.create_user(conn, %{
           username: name,
           email: email,
           is_guest: true,
           password: pass,
           confirm_password: pass
         }) do
      {:ok, user, conn} -> {user, conn}
      {:error, _, _} -> create_guest(conn)
    end
  end

  @doc """
  A User can have different active Heroes per game mode at the same time, which the User
  can switch freely at any time through the UI
  """
  def set_current_pve_hero!(user, hero_id), do: update!(user, %{current_pve_hero_id: hero_id})

  def set_current_pvp_hero!(user, hero_id), do: update!(user, %{current_pvp_hero_id: hero_id})

  @doc """
  Clears all active PVP heroes from the current players in the match.
  """
  def clear_active_players! do
    Repo.update_all(User, set: [current_pvp_hero_id: nil])
  end

  @doc """
  Increments duel counts and sets the duel_score map that is displayed on the user's profile
  Each user holds the score count of every other user they have dueled against
  """
  def duel_updates!(user, updates) do
    loser_id = updates[:loser_id] && Integer.to_string(updates[:loser_id])
    current_score = user.duel_score[loser_id] || 0
    duel_score = loser_id && Map.put(user.duel_score, loser_id, current_score + 1)
    extra_win = if updates[:duel_winner], do: 1, else: 0

    update!(user, %{
      duel_score: duel_score || user.duel_score,
      duel_wins: user.duel_wins + extra_win,
      duel_count: user.duel_count + 1,
      season_points: updates[:season_points] || user.season_points
    })
  end

  @doc """
  Lists Users by their ranking
  """
  def ranking(limit), do: UserQuery.ranking(limit) |> UserQuery.load() |> Repo.all()

  @doc """
  Updates all Users' ranking by their medal_count and XP
  """
  def update_ranking! do
    Repo.update_all(User, set: [ranking: nil])

    UserQuery.eligible_for_ranking(1000)
    |> Repo.all()
    |> Enum.with_index(1)
    |> Enum.each(fn {user, index} ->
      update!(user, %{ranking: index})
    end)
  end

  @doc """
  Grabs users with rankings close to the target user
  """
  def search(%{ranking: ranking}) when not is_nil(ranking) do
    {min, max} =
      if ranking <= 5 do
        {1, 10}
      else
        {ranking - 4, ranking + 4}
      end

    UserQuery.load()
    |> UserQuery.non_bots()
    |> UserQuery.non_guests()
    |> UserQuery.by_ranking(min, max)
    |> Repo.all()
  end

  def search(%{level: level, id: id} = user) do
    by_level =
      UserQuery.non_bots()
      |> UserQuery.non_guests()
      |> UserQuery.by_level(level)
      |> UserQuery.limit_by(9)
      |> UserQuery.load()
      |> Repo.all()

    [user] ++ Enum.filter(by_level, &(&1.id != id))
  end

  def manage_season_points!(%{current_pvp_hero: hero, season_points: current_points} = user) do
    new_points =
      if hero do
        current_points + hero.pvp_points
      else
        current_points
      end

    minimum = mininum_season_points_for(user)

    new_points = if new_points < minimum, do: minimum, else: new_points

    season_tier = Enum.find(1..7, 1, fn tier -> season_points_for(tier) > new_points end) - 1

    update!(user, %{season_tier: season_tier, season_points: new_points})
  end

  def season_points_for(tier) do
    case tier do
      1 -> 100
      2 -> 200
      3 -> 300
      4 -> 500
      5 -> 1000
      6 -> 2000
      7 -> 4000
      _ -> 0
    end
  end

  def update_collection!(user, hero_collection) do
    update!(user, %{hero_collection: hero_collection})
  end

  def increment_unread_messages_count_for_all_online_except(user) do
    query = UserQuery.online_users(User, 24) |> UserQuery.non_guests() |> UserQuery.exclude_user(user)
    Repo.update_all(query, inc: [unread_messages_count: 1])
  end

  def reset_unread_messages_count(user) do
    UserQuery.by_user(user)
    |> Repo.update_all(set: [unread_messages_count: 0])
  end

  # --------------------------------

  defp check_if_leveled(%{data: data, changes: changes} = changeset) do
    current_level = changes[:level] || data.level
    xp = changes[:experience] || 0
    diff = Moba.user_level_xp() - xp

    if diff <= 0 do
      changeset
      |> User.level_up(current_level, diff * -1)
      |> check_if_leveled()
    else
      changeset
    end
  end

  defp mininum_season_points_for(%{medal_count: medals}), do: medals * Moba.season_points_per_medal()
end
