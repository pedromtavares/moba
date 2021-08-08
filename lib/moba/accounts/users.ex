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
  def get!(id), do: Repo.get!(User, id)

  def get_with_unlocks!(id), do: get!(id) |> Repo.preload(:unlocks)

  def get_with_current_heroes!(id), do: get!(id) |> Repo.preload(current_pve_hero: :avatar, current_pvp_hero: :avatar)

  def get_by_username!(username), do: Repo.get_by!(User, username: username)

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
  def award_medals_and_shards(user, ranking) when ranking > 0 and ranking < 4 do
    {medals, shards} =
      case ranking do
        1 -> {3, 200}
        2 -> {2, 150}
        3 -> {1, 100}
      end

    update!(user, %{medal_count: user.medal_count + medals, shard_count: user.shard_count + shards})
  end

  def award_medals_and_shards(user, _), do: user

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
  Increments PVP counts and sets the pvp_score map that is displayed on the user's profile
  Each user holds the score count of every other user they have battled against
  """
  def pvp_updates!(user, updates) do
    loser_id = updates[:loser_user_id] && Integer.to_string(updates[:loser_user_id])
    current_score = user.pvp_score[loser_id] || 0
    pvp_score = loser_id && Map.put(user.pvp_score, loser_id, current_score + 1)

    extra_win = if updates[:pvp_wins], do: 1, else: 0
    extra_loss = if updates[:pvp_losses], do: 1, else: 0

    update!(user, %{
      pvp_score: pvp_score || user.pvp_score,
      pvp_points: updates[:pvp_points] || user.pvp_points,
      pvp_wins: user.pvp_wins + extra_win,
      pvp_losses: user.pvp_losses + extra_loss
    })
  end

  @doc """
  Users lose PVP points if they don't play in a round. This is to avoid having users
  stay on top of the ranking without playing, not giving others a chance to beat them.
  """
  def pvp_decay!(user) do
    diff = user.pvp_points - Moba.pvp_round_decay()
    points = if diff < 0, do: 0, else: diff
    update!(user, %{pvp_points: points})
  end

  @doc """
  Lists Users by their ranking
  """
  def ranking(limit), do: UserQuery.ranking(limit) |> Repo.all()

  @doc """
  Updates all Users' ranking by their medal_count and XP
  """
  def update_ranking! do
    Repo.update_all(User, set: [ranking: nil])

    UserQuery.eligible_for_ranking(100)
    |> Repo.all()
    |> Enum.with_index(1)
    |> Enum.each(fn {user, index} ->
      update!(user, %{ranking: index})
    end)
  end

  @doc """
  Updates all Users' shard_limit to the default daily amount
  """
  def reset_shard_limits! do
    limit = Moba.shard_limit()
    Repo.update_all(UserQuery.non_guests(), set: [shard_limit: limit])
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

    UserQuery.non_bots()
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

  def finish_pve!(user, hero_collection, shards) do
    update!(user, %{
      hero_collection: hero_collection,
      shard_count: user.shard_count + shards,
      shard_limit: user.shard_limit - shards
    })
  end

  def pve_shards_for(%{shard_limit: shard_limit}, league_tier) do
    reward =
      case league_tier do
        6 -> 100
        5 -> 50
        4 -> 40
        3 -> 30
        2 -> 20
        1 -> 10
        _ -> 0
      end

    if shard_limit - reward >= 0 do
      reward
    else
      shard_limit
    end
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
      # broadcast_level_up(data.id, current_level)

      changeset
      |> User.level_up(current_level, diff * -1)
      |> check_if_leveled()
    else
      changeset
    end
  end

  # This alert shows up as soon as the user levels up during a PVE battle
  defp broadcast_level_up(user_id, current_level) do
    MobaWeb.broadcast("user-#{user_id}", "alert", level_up_alert(current_level))
  end

  defp level_up_alert(current_level), do: %{level: current_level + 1, type: "battle"}

  defp mininum_season_points_for(%{medal_count: medals}), do: medals * Moba.season_points_per_medal()
end
