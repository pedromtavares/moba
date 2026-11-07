defmodule Moba.ArenaWinRateTest do
  use Moba.DataCase

  alias Game.Matches
  alias Game.Schema.{Match, Player, TrainingTeam}

  test "counts the latest 100 scored 3v3 results for the account" do
    player = create_player!()
    older_player = Repo.insert!(%Player{user_id: player.user_id})
    opponent = create_player!()

    result = %{player_id: player.id, opponent_id: opponent.id, winner_id: opponent.id, phase: "scored", team_size: 3}
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    first = Repo.insert!(struct!(Match, Map.merge(result, %{winner_id: player.id, updated_at: now})))
    Repo.insert_all(Match, List.duplicate(Map.merge(result, %{inserted_at: now, updated_at: now}), 99))

    Repo.insert!(struct!(Match, %{result | player_id: older_player.id, winner_id: older_player.id}))
    Repo.insert!(struct!(Match, %{result | winner_id: player.id, team_size: 5}))
    Repo.insert!(struct!(Match, %{result | winner_id: nil, phase: "started"}))
    team = Repo.insert!(%TrainingTeam{player_id: player.id, user_id: player.user_id, state: <<>>, phase: "finished"})
    Repo.insert!(struct!(Match, Map.merge(result, %{training_team_id: team.id, winner_id: player.id})))
    Game.Duels.create!(player, opponent, true)

    assert Matches.recent_results([player.id, opponent.id]) == %{
             player.id => %{wins: 1, matches: 100},
             opponent.id => %{wins: 0, matches: 0}
           }

    # A match started earlier can still be the most recently completed match.
    first |> Ecto.Changeset.change(updated_at: NaiveDateTime.add(now, 60)) |> Repo.update!()
    assert Matches.recent_results(player) == %{wins: 2, matches: 100}
  end

  test "daily cleanup preserves up to 100 old results without keeping all historical matches" do
    player = create_player!()
    opponent = create_player!()
    old = NaiveDateTime.utc_now() |> NaiveDateTime.add(-8 * 86_400) |> NaiveDateTime.truncate(:second)

    result = %{
      player_id: player.id,
      opponent_id: opponent.id,
      winner_id: player.id,
      phase: "scored",
      team_size: 3,
      inserted_at: old,
      updated_at: old
    }

    oldest = Repo.insert!(struct!(Match, result))
    legacy = Repo.insert!(struct!(Match, %{result | team_size: 5}))
    Repo.insert_all(Match, List.duplicate(result, 100))

    Moba.Cleaner.cleanup_old_records()

    refute Repo.get(Match, oldest.id)
    refute Repo.get(Match, legacy.id)
    assert Matches.recent_results(player) == %{wins: 100, matches: 100}
  end
end
