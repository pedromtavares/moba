defmodule Moba.CommunityActivityTest do
  use Moba.DataCase

  alias Moba.Game.{CommunityActivity, Duels, Matches}

  test "uses the latest meaningful event, including completed training on an older hero" do
    player = create_player!()
    opponent = create_player!()
    hero = create_base_hero(%{}, player) |> change(inserted_at: DateTime.to_naive(ago(300))) |> Repo.update!()
    match = completed_match(player, opponent, %{updated_at: ago(120)})
    assert %{kind: :match, id: id, result: :won} = activity(player)
    assert id == match.id

    Game.update_hero!(hero, %{finished_at: ago(60)})
    assert %{kind: :training_finished, id: id, avatar: "Phantom Assassin"} = activity(player)
    assert id == hero.id

    next = Game.create_hero!(%{name: "Next hero"}, player, base_avatar(), base_skills())
    assert %{kind: :training_started, id: id} = activity(player)
    assert id == next.id
  end

  test "automatic 5v5 matches and opponent-side manual matches are not player activity" do
    player = create_player!()
    opponent = create_player!()
    hero = create_base_hero(%{}, player) |> change(inserted_at: DateTime.to_naive(ago(300))) |> Repo.update!()
    completed_match(player, opponent, %{type: "auto"})
    completed_match(opponent, player)

    assert %{kind: :training_started, id: id} = activity(player)
    assert id == hero.id
  end

  test "season duels show the initiator's picks and live duels show each participant's own picks" do
    player = create_player!()
    opponent = create_player!()
    player_first = create_combat_hero(%{}, player)
    player_second = create_combat_hero(%{}, player, alternate_avatar())
    opponent_first = create_combat_hero(%{}, opponent)
    opponent_second = create_combat_hero(%{}, opponent, alternate_avatar())

    picks = %{
      player_first_pick_id: player_second.id,
      player_second_pick_id: player_first.id,
      opponent_first_pick_id: opponent_second.id,
      opponent_second_pick_id: opponent_first.id
    }

    season_duel = player |> Duels.create!(opponent, true) |> change(picks) |> Repo.update!()
    Duels.finish!(season_duel, %{winner: player, attacker_pvp_points: 5, defender_pvp_points: 0})

    activities = CommunityActivity.latest_for_players([player.id, opponent.id])
    assert %{kind: :season_duel, result: :won, pvp_roster: roster} = activities[player.id]
    assert Enum.map(roster, & &1.id) == [player_second.id, player_first.id]
    assert %{kind: :training_started} = activities[opponent.id]

    live_duel = player |> Duels.create!(opponent, false) |> change(picks) |> Repo.update!()
    Duels.finish!(live_duel, %{winner: opponent, attacker_pvp_points: -5, defender_pvp_points: 5})
    activities = CommunityActivity.latest_for_players([player.id, opponent.id])
    assert %{kind: :live_duel, result: :lost, opponent: name, pvp_roster: roster} = activities[player.id]
    assert name == Accounts.get_user!(opponent.user_id).username
    assert Enum.map(roster, & &1.id) == [player_second.id, player_first.id]
    assert %{kind: :live_duel, result: :won, pvp_roster: roster} = activities[opponent.id]
    assert Enum.map(roster, & &1.id) == [opponent_second.id, opponent_first.id]
  end

  test "ignores pending games, training duels, old events and other players" do
    player = create_player!()
    opponent = create_player!()
    Duels.create!(player, opponent, false)

    training = Duels.create!(player, opponent, true)
    training = training |> Game.Schema.Duel.changeset(%{type: "pve"}) |> Repo.update!()
    Duels.finish!(training, %{winner: player, attacker_pvp_points: 0, defender_pvp_points: 0})
    completed_match(player, opponent, %{updated_at: ago(8 * 86_400)})
    completed_match(opponent, player)

    assert CommunityActivity.latest_for_players([player.id]) == %{}
    assert CommunityActivity.latest_for_players([]) == %{}
  end

  test "recent players stay ordered by last user activity and supply artwork from the latest hero" do
    player = create_player!()
    opponent = create_player!()
    Accounts.get_user!(player.user_id) |> change(last_online_at: ago(120)) |> Repo.update!()
    Accounts.get_user!(opponent.user_id) |> change(last_online_at: ago(60)) |> Repo.update!()

    for i <- 1..7 do
      Game.create_hero!(%{name: "Recent #{i}"}, player, base_avatar(), base_skills())
    end

    before = Accounts.get_user!(player.user_id).last_online_at
    completed_match(player, opponent, %{type: "auto"})

    [first, second] =
      Admin.current_active_players()
      |> Enum.filter(&(&1.id in [player.id, opponent.id]))

    assert first.id == opponent.id
    assert second.id == player.id
    assert second.latest_hero.name == "Recent 7"
    assert second.user.last_online_at == before
    assert second.recent_activity.kind == :training_started
  end

  test "live availability requires both presence and accepting challenges" do
    available = create_player!(%{status: "available"})
    unavailable = create_player!(%{status: "unavailable"})
    offline = create_player!(%{status: "available"})

    ids = CommunityActivity.live_player_ids([available.id, unavailable.id])
    assert MapSet.member?(ids, available.id)
    refute MapSet.member?(ids, unavailable.id)
    refute MapSet.member?(ids, offline.id)
  end

  defp activity(player), do: CommunityActivity.latest_for_players([player.id])[player.id]

  defp completed_match(player, opponent, attrs \\ %{}) do
    {updated_at, attrs} = Map.pop(attrs, :updated_at, DateTime.utc_now())

    match =
      Matches.create!(
        Map.merge(
          %{
            player_id: player.id,
            opponent_id: opponent.id,
            winner_id: player.id,
            type: "manual",
            phase: "scored",
            player_picks: [],
            opponent_picks: [],
            generated_picks: []
          },
          attrs
        )
      )

    match |> change(updated_at: updated_at |> DateTime.truncate(:second) |> DateTime.to_naive()) |> Repo.update!()
  end

  defp ago(seconds), do: DateTime.utc_now() |> DateTime.add(-seconds) |> DateTime.truncate(:second)
end
