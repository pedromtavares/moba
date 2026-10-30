defmodule Moba.ArenaRewardsTest do
  use Moba.DataCase

  alias Moba.Game.{Arena, Duels, Matches}

  test "matches and duels share the first thirty daily rewards" do
    player = create_player!()
    opponent = create_player!(%{total_matches: 1})

    for _ <- 1..28, do: match(player, opponent)
    balance = Accounts.get_user!(player.user_id).shard_count
    Game.create_duel!(player, opponent, true)
    assert Arena.daily_reward_games(player) == 29
    assert Accounts.get_user!(player.user_id).shard_count == balance + 20

    assert Game.manual_matchmaking!(player)
    assert Arena.daily_reward_games(player) == 30
    assert Accounts.get_user!(player.user_id).shard_count == balance + 40

    Game.create_duel!(player, opponent, true)
    assert Accounts.get_user!(player.user_id).shard_count == balance + 40
  end

  test "live duels reward both participants according to their own allowance" do
    player = create_player!()
    opponent = create_player!()
    for _ <- 1..30, do: match(player, opponent)
    player_balance = Accounts.get_user!(player.user_id).shard_count
    opponent_balance = Accounts.get_user!(opponent.user_id).shard_count

    Game.create_duel!(player, opponent, false)

    assert Arena.daily_reward_games(player) == 31
    assert Arena.daily_reward_games(opponent) == 1
    assert Accounts.get_user!(player.user_id).shard_count == player_balance
    assert Accounts.get_user!(opponent.user_id).shard_count == opponent_balance + 20
  end

  test "automatic matches, another player's season duels, training and previous days do not use the allowance" do
    player = create_player!()
    opponent = create_player!()
    match(player, opponent, %{type: "auto"})
    Duels.create!(opponent, player, true)
    training = Duels.create!(player, opponent, true)
    training |> Game.Schema.Duel.changeset(%{type: "pve"}) |> Repo.update!()
    previous = match(player, opponent)
    reset_at = Moba.current_season().last_pvp_update_at

    Repo.update_all(from(m in Game.Schema.Match, where: m.id == ^previous.id),
      set: [inserted_at: Timex.shift(reset_at, seconds: -1)]
    )

    assert Arena.daily_reward_games(player) == 0
  end

  test "repeated plays with a stale player do not overwrite the shard balance" do
    player = create_player!()
    opponent = create_player!()
    balance = Accounts.get_user!(player.user_id).shard_count
    Game.create_duel!(player, opponent, true)
    Game.create_duel!(player, opponent, true)
    assert Accounts.get_user!(player.user_id).shard_count == balance + 40
  end

  test "no opponent means no game and no reward" do
    player = create_player!(%{pvp_tier: 99})
    balance = Accounts.get_user!(player.user_id).shard_count
    refute Game.manual_matchmaking!(player)
    assert Arena.daily_reward_games(player) == 0
    assert Accounts.get_user!(player.user_id).shard_count == balance
  end

  defp match(player, opponent, attrs \\ %{}) do
    Matches.create!(
      Map.merge(
        %{
          player_id: player.id,
          opponent_id: opponent.id,
          player_picks: [],
          opponent_picks: [],
          generated_picks: [],
          type: "manual"
        },
        attrs
      )
    )
  end
end
