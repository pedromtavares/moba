defmodule Moba.Accounts.Users do
  @moduledoc """
  Manages User records and progression via levels, shards and medals.

  Also includes logic for user-related PVP handling, which should be
  extracted to the Game context at some point (Player entity perhaps?).
  """

  alias Moba.{Repo, Accounts}
  alias Accounts.Schema.User
  alias Accounts.Query.UserQuery

  @max_season_tier Moba.max_season_tier()

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
    |> UserQuery.exclude_ids([user.id])
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

  def set_current_pve_hero!(user, hero_id), do: update!(user, %{current_pve_hero_id: hero_id})

  @doc """
  Increments duel counts and sets the duel_score map that is displayed on the user's profile
  Each user holds the score count of every other user they have dueled against
  """
  def duel_updates!(user, updates) do
    loser_id = updates[:loser_id] && Integer.to_string(updates[:loser_id])
    current_score = user.duel_score[loser_id] || 0
    duel_score = loser_id && Map.put(user.duel_score, loser_id, current_score + 1)
    extra_win = if updates[:duel_winner], do: 1, else: 0
    season_points = updates[:season_points] || user.season_points
    season_tier = season_tier_for(season_points)

    update!(user, %{
      duel_score: duel_score || user.duel_score,
      duel_wins: user.duel_wins + extra_win,
      duel_count: user.duel_count + 1,
      season_points: season_points,
      season_tier: season_tier
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
  def search(%{is_bot: true}) do
    UserQuery.by_season_points()
    |> UserQuery.bots()
    |> UserQuery.load()
    |> Repo.all()
  end

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

  def season_tier_for(points) when points < 4000 do
    Enum.find(0..7, fn tier -> season_points_for(tier + 1) > points end)
  end

  def season_tier_for(_), do: 7

  def update_collection!(user, hero_collection) do
    update!(user, %{hero_collection: hero_collection})
  end

  def increment_unread_messages_count_for_all_online_except(user) do
    query = UserQuery.online_users(User, 24) |> UserQuery.non_guests() |> UserQuery.exclude_ids([user.id])
    Repo.update_all(query, inc: [unread_messages_count: 1])
  end

  def reset_unread_messages_count(user) do
    UserQuery.by_user(user)
    |> Repo.update_all(set: [unread_messages_count: 0])
  end

  def shard_buyback_price(%{shard_count: count}) do
    minimum = Moba.shard_buyback_minimum()
    percentage_price = trunc(count * minimum / 100)

    if percentage_price > minimum do
      percentage_price
    else
      minimum
    end
  end

  def shard_buyback!(%{shard_count: count} = user) do
    price = shard_buyback_price(user)

    if count >= price do
      update!(user, %{shard_count: count - price})
    else
      nil
    end
  end

  def normal_matchmaking(user) do
    opponent = normal_matchmaking_opponent(user)

    if opponent do
      update!(user, %{shard_count: user.shard_count + Moba.normal_matchmaking_shards()})
      opponent
    end
  end

  def elite_matchmaking(user) do
    opponent = elite_matchmaking_opponent(user)

    if opponent do
      update!(user, %{shard_count: user.shard_count + Moba.elite_matchmaking_shards()})
      opponent
    end
  end

  def manage_match_history(%{match_history: history} = user, opponent) do
    timeout = Timex.shift(Timex.now(), hours: Moba.match_timeout_in_hours())
    history = Map.put(history, Integer.to_string(opponent.id), timeout)
    update!(user, %{match_history: history})
  end

  def normal_matchmaking_count(user) do
    normal_matchmaking_query(user) |> Repo.aggregate(:count)
  end

  def elite_matchmaking_count(user) do
    elite_matchmaking_query(user) |> Repo.aggregate(:count)
  end

  def closest_bot_time(%{match_history: history}) do
    Map.values(history) |> Enum.sort() |> List.first()
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

  defp match_exclusions(%{match_history: history}) do
    Enum.reduce(history, [], fn {id, time}, acc ->
      parsed = Timex.parse!(time, "{ISO:Extended:Z}")

      if Timex.before?(parsed, Timex.now()) do
        acc
      else
        acc ++ [id]
      end
    end)
  end

  defp maximum_tier(tier) when tier > @max_season_tier, do: @max_season_tier
  defp maximum_tier(tier), do: tier

  defp minimum_tier(tier) when tier < 0, do: 0
  defp minimum_tier(tier), do: tier

  def normal_matchmaking_opponent(%{season_tier: tier}) when tier < 0, do: nil

  def normal_matchmaking_opponent(%{season_tier: tier} = user) do
    result = normal_matchmaking_query(user) |> Repo.all() |> List.first()

    if result, do: result, else: normal_matchmaking(%{user | season_tier: tier - 1})
  end

  def elite_matchmaking_opponent(%{season_tier: tier}) when tier > @max_season_tier, do: nil

  def elite_matchmaking_opponent(%{season_tier: tier} = user) do
    result = elite_matchmaking_query(user) |> Repo.all() |> List.first()

    if result, do: result, else: elite_matchmaking(%{user | season_tier: tier + 1})
  end

  defp normal_matchmaking_query(%{season_tier: tier} = user) do
    exclusions = match_exclusions(user)
    min_tier = minimum_tier(tier - 1)

    UserQuery.season_search(min_tier, tier) |> UserQuery.exclude_ids(exclusions)
  end

  defp elite_matchmaking_query(%{season_tier: tier} = user) do
    exclusions = match_exclusions(user)
    min_tier = maximum_tier(tier + 1)
    max_tier = maximum_tier(tier + 2)

    UserQuery.season_search(min_tier, max_tier) |> UserQuery.exclude_ids(exclusions)
  end
end
