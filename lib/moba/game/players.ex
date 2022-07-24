defmodule Moba.Game.Players do
  @moduledoc """
  Manages Match records and queries.
  See Moba.Game.Schema.Match for more info.
  """

  alias Moba.{Repo, Game}
  alias Game.Schema.Player
  alias Game.Query.PlayerQuery

  @max_pvp_tier Moba.max_pvp_tier()

  def add_total_farm!(%{player: player} = hero) do
    update_player!(player, %{total_farm: player.total_farm + hero.total_gold_farm + hero.total_xp_farm})
  end

  def bot_opponent(player) do
    exclusions = match_exclusions(player) ++ [player.id]

    PlayerQuery.bot_opponents(player.pvp_tier)
    |> PlayerQuery.exclude_ids(exclusions)
    |> PlayerQuery.limit_by(1)
    |> Repo.all()
    |> List.first()
  end

  def bot_ranking, do: PlayerQuery.bots() |> PlayerQuery.by_pvp_points() |> Repo.all()

  def closest_bot_time(%{match_history: history}) do
    Map.values(history) |> Enum.sort() |> List.first()
  end

  def create_player!(attrs \\ %{}) do
    %Player{}
    |> Player.changeset(attrs)
    |> Repo.insert!()
  end

  def duel_opponents(player, online_ids) do
    PlayerQuery.non_bots()
    |> PlayerQuery.non_guests()
    |> PlayerQuery.with_status("available")
    |> PlayerQuery.exclude_ids([player.id])
    |> PlayerQuery.with_ids(online_ids)
    |> Repo.all()
    |> Repo.preload(:user)
  end

  @doc """
  Increments duel counts and sets the duel_score map that is displayed on the player's profile
  Each player holds the score count of every other player they have dueled against
  """
  def duel_updates!(player, duel_type, updates) do
    pvp_points = updates[:pvp_points] || player.pvp_points
    pvp_tier = pvp_tier_for(pvp_points)
    base_updates = %{pvp_points: pvp_points, pvp_tier: pvp_tier}

    score_updates =
      if duel_type == "pvp" do
        loser_id = updates[:loser_id] && Integer.to_string(updates[:loser_id])
        current_score = player.duel_score[loser_id] || 0
        duel_score = loser_id && Map.put(player.duel_score, loser_id, current_score + 1)

        %{
          duel_score: duel_score || player.duel_score
        }
      else
        %{}
      end

    update_player!(player, Map.merge(base_updates, score_updates))
  end

  def elite_matchmaking_count(player) do
    elite_matchmaking_query(player) |> Repo.aggregate(:count)
  end

  def elite_matchmaking_opponent(player) do
    elite_matchmaking_query(player) |> PlayerQuery.limit_by(1) |> Repo.all() |> List.first()
  end

  def get_player!(id), do: PlayerQuery.load() |> Repo.get!(id)

  def get_player_from_user!(user_id), do: Repo.get_by(PlayerQuery.load(), user_id: user_id)

  def manage_match_history(%{match_history: history} = player, opponent) do
    timeout = Timex.shift(Timex.now(), hours: Moba.match_timeout_in_hours())
    history = Map.put(history, Integer.to_string(opponent.id), timeout)
    update_player!(player, %{match_history: history})
  end

  def matchmaking_opponent(player) do
    elite_matchmaking_opponent(player) || normal_matchmaking_opponent(player)
  end

  def normal_matchmaking_count(player) do
    normal_matchmaking_query(player) |> Repo.aggregate(:count)
  end

  def normal_matchmaking_opponent(player) do
    normal_matchmaking_query(player) |> PlayerQuery.limit_by(1) |> Repo.all() |> List.first()
  end

  def pvp_points_for(tier) do
    case tier do
      1 -> 30
      2 -> 60
      3 -> 100
      4 -> 130
      5 -> 160
      6 -> 200
      7 -> 230
      8 -> 260
      9 -> 300
      10 -> 330
      11 -> 360
      12 -> 400
      13 -> 430
      14 -> 460
      15 -> 500
      16 -> 600
      17 -> 750
      18 -> 1000
      _ -> 0
    end
  end

  @doc """
  Lists Players by their ranking
  """
  def pvp_ranking(limit), do: PlayerQuery.ranking(limit) |> Repo.all() |> Repo.preload(:user)

  def pvp_tier_for(points) when points < 1000 do
    Enum.find(0..18, fn tier -> pvp_points_for(tier + 1) > points end)
  end

  def pvp_tier_for(_), do: 18

  def set_player_available!(player), do: update_player!(player, %{status: "available"})

  def set_player_unavailable!(player), do: update_player!(player, %{status: "unavailable"})

  def set_current_pve_hero!(player, hero_id), do: update_player!(player, %{current_pve_hero_id: hero_id})

  def update_collection!(player, hero_collection) do
    update_player!(player, %{hero_collection: hero_collection})
  end

  def update_player!(%Player{} = player, attrs) do
    player
    |> Player.changeset(attrs)
    |> Repo.update!()
  end

  def update_preferences!(player, preferences) do
    current_preferences = Map.from_struct(player.preferences)
    update_player!(player, %{preferences: Map.merge(current_preferences, preferences)})
  end

  def update_tutorial_step!(player, step), do: update_player!(player, %{tutorial_step: step})

  @doc """
  Updates all Players' ranking
  """
  def update_ranking! do
    Repo.update_all(Player, set: [ranking: nil])

    PlayerQuery.eligible_for_ranking(1000)
    |> Repo.all()
    |> Enum.with_index(1)
    |> Enum.each(fn {player, index} ->
      update_player!(player, %{ranking: index})
    end)
  end

  # --------------------------------

  defp elite_matchmaking_query(%{pvp_tier: player_tier, pvp_points: player_points} = player) do
    exclusions = match_exclusions(player) ++ [player.id]
    tier = maximum_tier(player_tier + 1)

    PlayerQuery.elite_opponents(tier, player_points) |> PlayerQuery.exclude_ids(exclusions)
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

  defp maximum_tier(tier) when tier > @max_pvp_tier, do: @max_pvp_tier
  defp maximum_tier(tier), do: tier

  defp normal_matchmaking_query(%{pvp_tier: player_tier, pvp_points: player_points} = player) do
    exclusions = match_exclusions(player) ++ [player.id]

    PlayerQuery.normal_opponents(player_tier, player_points) |> PlayerQuery.exclude_ids(exclusions)
  end
end
