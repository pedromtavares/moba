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
    UserQuery.set_online_query(user)
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
  medal_count is what ultimately ranks who is the best player in the game
  """
  def award_medals_and_shards(user, ranking) do
    total =
      case ranking do
        1 -> 3
        2 -> 2
        3 -> 1
        _ -> 0
      end

    update!(user, %{medal_count: user.medal_count + total, shard_count: user.shard_count + total})
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

  @doc """
  A User can have different active Heroes per game mode at the same time, which the User
  can switch freely at any time through the UI
  """
  def set_current_pve_hero!(user, hero_id), do: update!(user, %{current_pve_hero_id: hero_id})

  def set_current_pvp_hero!(user, hero_id), do: update!(user, %{current_pvp_hero_id: hero_id})

  @doc """
  Clears all active heroes from the current players in the match
  Users will need to create new Heroes for the Jungle and/or pick a new Hero for the Arena
  Jungle heroes that haven't finished all of their available battles will not be cleared
  """
  def clear_active_players! do
    UserQuery.current_players()
    |> Repo.all()
    |> Repo.preload(:current_pve_hero)
    |> Enum.map(fn user ->
      if can_clear_pve_hero?(user) do
        update!(user, %{current_pvp_hero_id: nil, current_pve_hero_id: nil})
      else
        set_current_pvp_hero!(user, nil)
      end
    end)
  end

  def clear_pve_hero!(user), do: (can_clear_pve_hero?(user) && set_current_pve_hero!(user, nil)) || user

  def can_clear_pve_hero?(user) do
    %{current_pve_hero: pve_hero} = Repo.preload(user, :current_pve_hero)
    pve_hero && pve_hero.pve_battles_available == 0
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
    by_level = UserQuery.non_bots()
    |> UserQuery.non_guests()
    |> UserQuery.by_level(level)
    |> UserQuery.limit_by(9)
    |> Repo.all()

    [user] ++ Enum.filter(by_level, &(&1.id != id))
  end

  # --------------------------------

  defp check_if_leveled(%{data: data, changes: changes} = changeset) do
    current_level = changes[:level] || data.level
    xp = changes[:experience] || 0
    shard_count = changes[:shard_count] || data.shard_count
    diff = Moba.user_level_xp() - xp

    if diff <= 0 do
      broadcast_level_up(data.id, current_level)

      changeset
      |> User.level_up(current_level, diff * -1, shard_count)
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
end
