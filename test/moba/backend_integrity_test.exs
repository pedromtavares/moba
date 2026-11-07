defmodule Moba.BackendIntegrityTest do
  use Moba.DataCase
  alias Moba.Accounts.Schema.Unlock
  alias Moba.Engine.Schema.Turn

  test "combat rejects a higher rank of an otherwise owned skill" do
    first = create_base_hero(%{total_hp: 10_000, total_mp: 1_000})
    other = create_base_hero(%{total_hp: 10_000, total_mp: 1_000})
    assert Enum.find(first.skills, &(&1.code == "decay")).level == 1
    forged = Game.get_skill_by_code!("decay", true, 5)
    battle = create_basic_battle(first, other)
    updated = Engine.continue_battle!(battle, %{skill: forged, item: nil})
    assert List.last(updated.turns).skill_code == "basic_attack"
  end

  test "simultaneous requests from the same battle snapshot commit one turn" do
    first = create_base_hero(%{total_hp: 10_000, total_mp: 1_000})
    other = create_base_hero(%{total_hp: 10_000, total_mp: 1_000})
    battle = create_basic_battle(first, other)
    supervisor = start_supervised!(Task.Supervisor)

    results =
      Task.Supervisor.async_stream_nolink(supervisor, [battle, battle], fn snapshot ->
        Engine.continue_battle!(snapshot, %{skill: nil, item: nil})
      end)
      |> Enum.to_list()

    assert Enum.all?(results, &match?({:ok, _}, &1))
    stored = Engine.get_battle!(battle.id)
    assert Enum.map(stored.turns, & &1.number) == [1]
    # The database also rejects duplicates from callers bypassing the engine.
    duplicate =
      Repo.insert!(%Turn{battle_id: battle.id, number: 1},
        on_conflict: :nothing,
        conflict_target: [:battle_id, :number]
      )

    assert duplicate.id == nil
  end

  test "wrong players and spectators cannot advance a battle at the engine boundary" do
    first = create_base_hero(%{total_hp: 10_000})
    other = create_base_hero(%{total_hp: 10_000})
    battle = create_basic_battle(first, other)
    unchanged = Engine.continue_battle!(battle, %{skill: nil, item: nil, player_id: other.player_id})
    assert unchanged.turns == []
    unchanged = Engine.continue_battle!(battle, %{auto: true, timeout: true, player_id: -1})
    assert unchanged.turns == []
    assert length(Engine.continue_battle!(battle, %{skill: nil, item: nil, player_id: first.player_id}).turns) == 1
  end

  test "completed farming grants rewards once even when the caller reuses its snapshot" do
    hero = create_base_hero(%{pve_current_turns: 5})

    for turns <- [-10, 0, 6] do
      assert Game.start_farming!(hero, "mining", turns).pve_state == "alive"
    end

    farming = Game.start_farming!(hero, "mining", 5)
    assert Game.finish_farming!(farming).pve_state == "mining"

    ready =
      Game.update_hero!(farming, %{
        pve_farming_started_at: DateTime.add(DateTime.utc_now(), -5 * Moba.seconds_per_turn() - 1)
      })

    finished = Game.finish_farming!(ready)
    assert finished.gold > hero.gold
    assert finished.pve_current_turns == 0
    target_ids = Enum.map(Game.list_targets(finished), & &1.id)
    assert Game.finish_farming!(ready).gold == finished.gold
    assert Enum.map(Game.list_targets(finished), & &1.id) == target_ids
    assert length(Game.get_hero!(hero.id).pve_farming_rewards) == 1
  end

  test "simultaneous unlock purchases use the stored balance and never charge for owned content" do
    hero = create_base_hero()
    user = Accounts.update_user!(hero.player.user, %{shard_count: 150})
    choices = [Game.get_avatar_by_code!("bloodseeker"), Game.get_avatar_by_code!("leshrac")]
    supervisor = start_supervised!(Task.Supervisor)

    results =
      Task.Supervisor.async_stream_nolink(supervisor, choices, &Accounts.buy_unlock!(user, &1)) |> Enum.to_list()

    assert Enum.all?(results, &match?({:ok, _}, &1))
    stored = Accounts.get_user_with_unlocks!(user.id)
    assert stored.shard_count == 0
    assert length(stored.unlocks) == 1
    owned = Enum.find(choices, &(&1.code == hd(stored.unlocks).resource_code))
    stored = Accounts.update_user!(stored, %{shard_count: 300})
    assert Accounts.buy_unlock!(stored, owned).shard_count == 300

    duplicate =
      Repo.insert!(%Unlock{user_id: user.id, resource_code: owned.code},
        on_conflict: :nothing,
        conflict_target: [:user_id, :resource_code]
      )

    assert duplicate.id == nil
  end

  test "shard rewards add to the current balance instead of overwriting purchases" do
    hero = create_base_hero()
    user = Accounts.update_user!(hero.player.user, %{shard_count: 150})
    stale = %{hero.player | user: user}
    Accounts.buy_unlock!(user, Game.get_avatar_by_code!("bloodseeker"))
    assert Moba.reward_shards!(stale, 20).shard_count == 20
  end

  test "a valid 3v3 lineup finishes and can only be scored once" do
    player = create_player!()
    opponent = create_player!()

    picks =
      for _ <- 1..3 do
        Game.create_hero!(
          %{name: "Ready", finished_at: Timex.now(), league_tier: 6},
          player,
          strong_avatar(),
          base_skills()
        )
      end

    others = for _ <- 1..3, do: Game.create_hero!(%{name: "Opponent"}, opponent, weak_avatar(), base_skills())

    match =
      Moba.Game.Matches.create!(%{
        player_id: player.id,
        opponent_id: opponent.id,
        player_picks: [],
        opponent_picks: Enum.map(others, & &1.id),
        generated_picks: [],
        type: "manual"
      })

    ids = Enum.map(picks, & &1.id)
    assert {:ok, finished} = Game.start_match(match, player, ids)
    assert finished.phase == "scored"
    assert finished.winner_id == player.id
    assert Game.get_player!(player.id).total_matches == 1
    assert {:error, :invalid_lineup} = Game.start_match(match, player, ids)
    Game.continue_match!(match)
    assert Game.get_player!(player.id).total_matches == 1
  end

  test "a historical 5v5 match retains its five-hero win condition" do
    player = create_player!()
    opponent = create_player!()

    picks =
      for _ <- 1..5 do
        Game.create_hero!(
          %{name: "Ready", finished_at: Timex.now(), league_tier: 6},
          player,
          strong_avatar(),
          base_skills()
        )
      end

    others = for _ <- 1..5, do: Game.create_hero!(%{name: "Opponent"}, opponent, weak_avatar(), base_skills())

    match =
      Moba.Game.Matches.create!(%{
        team_size: 5,
        player_id: player.id,
        opponent_id: opponent.id,
        player_picks: [],
        opponent_picks: Enum.map(others, & &1.id),
        generated_picks: [],
        type: "manual"
      })

    ids = Enum.map(picks, & &1.id)
    assert {:ok, finished} = Game.start_match(match, player, ids)
    assert finished.phase == "scored"
    assert finished.winner_id == player.id
    assert Game.get_player!(player.id).total_matches == 1
    assert {:error, :invalid_lineup} = Game.start_match(match, player, ids)
    Game.continue_match!(match)
    assert Game.get_player!(player.id).total_matches == 1
  end

  test "registration cannot claim a registered player's retained session id" do
    hero = create_base_hero()
    newcomer = create_user()
    Moba.after_registration(newcomer, hero.player_id)
    assert Game.get_player!(hero.player_id).user_id == hero.player.user_id
  end
end
