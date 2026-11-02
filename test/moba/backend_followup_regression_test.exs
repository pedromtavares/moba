defmodule Moba.BackendFollowupRegressionTest do
  use Moba.DataCase

  import ExUnit.CaptureLog

  test "timeouts advance persisted battles before and after the first turn" do
    for initial_turns <- [0, 1] do
      first = create_base_hero(%{total_hp: 100_000})
      second = create_base_hero(%{total_hp: 100_000})
      battle = create_basic_battle(first, second)

      battle =
        if initial_turns == 1,
          do: Engine.continue_battle!(battle, %{skill: nil, item: nil, player_id: first.player_id}),
          else: battle

      old = NaiveDateTime.utc_now() |> NaiveDateTime.add(-Moba.turn_timer_in_seconds() - 2)

      case List.last(battle.turns) do
        nil -> Repo.update_all(from(b in Engine.Schema.Battle, where: b.id == ^battle.id), set: [inserted_at: old])
        turn -> Repo.update_all(from(t in Engine.Schema.Turn, where: t.id == ^turn.id), set: [inserted_at: old])
      end

      battle = Engine.get_battle!(battle.id)
      advanced = Engine.continue_battle!(battle, %{auto: true, timeout: true, player_id: first.player_id})
      assert length(advanced.turns) == initial_turns + 1
    end
  end

  test "timeouts cannot skip an unexpired turn or act for a spectator" do
    first = create_base_hero(%{total_hp: 100_000})
    second = create_base_hero(%{total_hp: 100_000})
    battle = create_basic_battle(first, second)
    assert Engine.continue_battle!(battle, %{auto: true, timeout: true, player_id: first.player_id}).turns == []

    old = NaiveDateTime.utc_now() |> NaiveDateTime.add(-Moba.turn_timer_in_seconds() - 2)
    Repo.update_all(from(b in Engine.Schema.Battle, where: b.id == ^battle.id), set: [inserted_at: old])
    battle = Engine.get_battle!(battle.id)
    assert Engine.continue_battle!(battle, %{auto: true, timeout: true, player_id: -1}).turns == []
  end

  test "hero notifications wait for the outer commit and observe the committed state" do
    hero = create_base_hero()
    MobaWeb.subscribe("hero-#{hero.id}")
    owner = self()

    assert {:ok, :done} =
             Repo.transaction(fn ->
               assert {:ok, _} = Repo.transaction(fn -> Game.update_hero!(hero, %{gold: 1234}) end)

               Repo.after_commit(fn ->
                 send(owner, {:committed, Repo.in_transaction?(), Game.get_hero!(hero.id).gold})
               end)

               refute_received {"hero", _}
               refute_received {:committed, _, _}
               :done
             end)

    assert_receive {"hero", %{id: id}}
    assert id == hero.id
    assert_receive {:committed, false, 1234}
  end

  test "rollback and exceptions discard nested notifications and restore immediate delivery" do
    hero = create_base_hero()
    channel = "hero-#{hero.id}"
    MobaWeb.subscribe(channel)

    assert {:error, :cancelled} =
             Repo.transaction(fn ->
               Repo.transaction(fn -> Game.update_hero!(hero, %{gold: 1234}) end)
               Repo.rollback(:cancelled)
             end)

    refute_received {"hero", _}
    assert Game.get_hero!(hero.id).gold == hero.gold

    assert_raise RuntimeError, "cancel", fn ->
      Repo.transaction(fn ->
        Game.broadcast_to_hero(hero.id)
        raise "cancel"
      end)
    end

    refute_received {"hero", _}
    Game.broadcast_to_hero(hero.id)
    assert_receive {"hero", %{id: id}}
    assert id == hero.id
    refute_received {"hero", _}
  end

  test "Multi failures discard notifications and successful transact flushes them in order" do
    channel = "commit-probe-#{System.unique_integer([:positive])}"
    MobaWeb.subscribe(channel)

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.run(:notify, fn _, _ ->
        MobaWeb.broadcast(channel, "step", 1)
        {:ok, :queued}
      end)
      |> Ecto.Multi.run(:fail, fn _, _ -> {:error, :cancelled} end)

    assert {:error, :fail, :cancelled, _} = Repo.transaction(multi)
    refute_received {"step", _}

    assert {:ok, :done} =
             Repo.transact(fn ->
               MobaWeb.broadcast(channel, "step", 1)
               Repo.transaction(fn -> MobaWeb.broadcast(channel, "step", 2) end)
               MobaWeb.broadcast(channel, "step", 3)
               refute_received {"step", _}
               {:ok, :done}
             end)

    assert_receive {"step", 1}
    assert_receive {"step", 2}
    assert_receive {"step", 3}
  end

  test "duel phase notifications are discarded when the outer battle operation rolls back" do
    first = create_base_hero(%{finished_at: DateTime.utc_now(), league_tier: 6})
    second = create_base_hero(%{finished_at: DateTime.utc_now(), league_tier: 6})
    duel = Game.create_duel!(first.player, second.player, false)
    MobaWeb.subscribe("duel-#{duel.id}")

    assert {:error, :cancelled} =
             Repo.transaction(fn ->
               Game.pick_duel_hero(duel, first.player, first)
               refute_received {"phase", _}
               Repo.rollback(:cancelled)
             end)

    assert Game.get_duel!(duel.id).phase == "player_first_pick"
    refute_received {"phase", _}

    Game.pick_duel_hero(duel, first.player, first)
    assert_receive {"phase", "opponent_first_pick"}
    assert Game.get_duel!(duel.id).player_first_pick_id == first.id
  end

  test "automatic matchmaking commits successful matches around a failure and only claims an interval once" do
    first = automatic_player(0, 3000)
    broken = automatic_player(1, 2000)
    last = automatic_player(2, 1000)

    Repo.update_all(from(h in Game.Schema.Hero, where: h.player_id == ^broken.id), set: [total_hp: nil])

    Game.update_season!(Game.current_season(), %{
      last_server_update_at: DateTime.add(DateTime.utc_now(), -1801)
    })

    log = capture_log(fn -> Conductor.season_tick!() end)
    assert log =~ "Automatic match failed for player ##{broken.id}"

    for player <- [first, last] do
      assert [%{phase: "scored"}] = Game.list_matches(player)
      assert Game.get_player!(player.id).daily_matches == 1
    end

    assert Game.list_matches(broken) == []
    assert Game.get_player!(broken.id).daily_matches == 0
    assert DateTime.diff(DateTime.utc_now(), Game.current_season().last_server_update_at) < 60

    Conductor.season_tick!()
    for player <- [first, last], do: assert(length(Game.list_matches(player)) == 1)
    assert Game.list_matches(broken) == []
  end

  defp automatic_player(tier, points) do
    player = create_player!(%{pve_tier: 1, pvp_tier: tier, pvp_points: points, hero_collection: [%{"tier" => 6}]})
    create_player!(%{pvp_tier: tier, total_matches: 1})

    for _ <- 1..5 do
      Game.create_hero!(
        %{name: "Ready", finished_at: DateTime.utc_now(), league_tier: 6, atk: 100_000, total_hp: 1000, speed: 100},
        player,
        base_avatar(),
        base_skills()
      )
    end

    player
  end
end
