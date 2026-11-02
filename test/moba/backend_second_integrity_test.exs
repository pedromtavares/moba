defmodule Moba.BackendSecondIntegrityTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest
  import Ecto.Query
  alias Moba.Repo

  test "training rejects dead, finished and archived heroes even with a stale alive snapshot", %{conn: conn} do
    for attrs <- [%{pve_state: "dead"}, %{finished_at: DateTime.utc_now()}, %{archived_at: DateTime.utc_now()}] do
      hero = create_base_hero(%{pve_tier: 2, pve_current_turns: 3})
      Game.update_hero!(hero, attrs)
      assert {:error, _} = Game.start_league_battle!(hero)
      refute Engine.latest_battle(hero.id)
    end

    hero = create_base_hero(%{pve_state: "dead", pve_tier: 2})
    {:ok, view, _} = conn |> log_in_player(player_id: hero.player_id) |> live("/training")
    render_click(view, "league")
    refute Engine.latest_battle(hero.id)
  end

  test "repeated training starts reuse the pending battle and spend only one turn" do
    hero = create_base_hero(%{pve_tier: 2, pve_current_turns: 3, total_hp: 100_000})
    target = Game.list_targets(hero) |> hd() |> then(&Game.get_target!(&1.id))
    first = Game.start_pve_battle!(target)
    assert first.id == Game.start_pve_battle!(target).id
    assert Game.get_hero!(hero.id).pve_current_turns == 2
  end

  test "battle equipment and abilities remain consistent after reload and equipment changes" do
    first =
      create_base_hero(%{gold: 100_000, total_hp: 20_000, total_mp: 1_000})
      |> Game.buy_item!(Game.get_item_by_code!("satanic"))

    other = create_base_hero(%{total_hp: 20_000, total_mp: 1_000})
    battle = create_basic_battle(first, other)
    battle = Engine.continue_battle!(battle, %{skill: nil, item: nil})

    changed =
      Game.get_hero!(first.id)
      |> Game.sell_item!(Game.get_item_by_code!("satanic"))
      |> Game.buy_item!(alternate_item())

    battle = Engine.continue_battle!(Engine.get_battle!(battle.id), %{skill: nil, item: nil})
    turn = Engine.build_turn(Engine.get_battle!(battle.id))
    battler = if turn.attacker.hero_id == first.id, do: turn.attacker, else: turn.defender
    assert Enum.any?(battler.passive_items ++ battler.active_items, &(&1.code == "satanic"))
    refute Enum.any?(battler.passive_items ++ battler.active_items, &(&1.code == alternate_item().code))
    assert battler.total_hp == first.total_hp + first.item_hp
    assert battler.total_hp != changed.total_hp + changed.item_hp
  end

  test "live duel participants cannot join another active duel or collect duplicate rewards" do
    first = create_player!()
    other = create_player!()
    third = create_player!()
    before = Accounts.get_user!(first.user_id).shard_count
    duel = Game.create_duel!(first, other, false)
    refute Game.create_duel!(first, other, false)
    refute Game.create_duel!(third, other, false)
    refute Game.create_duel!(other, third, true)
    assert Game.Duels.pending_duel(first).id == duel.id
    assert Accounts.get_user!(first.user_id).shard_count == before + 20
  end

  test "being the automated opponent does not block starting a player's own duel" do
    first = create_player!()
    other = create_player!()
    third = create_player!()
    Game.create_duel!(first, other, true)
    refute Game.Duels.pending_duel(other)
    assert Game.create_duel!(other, third, false)
  end

  test "reset requests are limited without exposing account existence", %{conn: conn} do
    Moba.AccountsFixtures.mail_sender_fixture()
    user = create_user()
    {:ok, view, _} = live(conn, "/users/reset_password")

    for _ <- 1..10 do
      view |> form("#reset_password_form", user: %{email: user.email}) |> render_submit()
    end

    query = from t in Accounts.UserToken, where: t.user_id == ^user.id and t.context == "reset_password"
    assert Repo.aggregate(query, :count) == 1
    assert render(view) =~ "If your email is in our system"

    Repo.update_all(query,
      set: [inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(-61) |> NaiveDateTime.truncate(:second)]
    )

    assert {:ok, _} = Accounts.deliver_user_reset_password_instructions(user, &"https://example.invalid/#{&1}")
    assert Repo.aggregate(query, :count) == 2
  end

  test "player creation is idempotent per account and season and ignores duplicate legacy records" do
    user = create_user()
    first = Game.create_player!(%{user_id: user.id})
    assert first.season_id == Game.current_season().id
    assert Game.create_player!(%{user_id: user.id}).id == first.id
    legacy = Repo.insert!(%Game.Schema.Player{user_id: user.id})
    assert Moba.player_for(user).id == first.id
    assert Repo.get!(Game.Schema.Player, legacy.id)
    guest = Game.start_guest!("season-guest-#{user.id}", base_avatar(), creation_skills())
    assert guest.season_id == first.season_id
  end

  test "failed resource publication rolls back resource flags, copies and season version" do
    ultimate = base_ultimate()
    Repo.update!(Ecto.Changeset.change(ultimate, enabled: false))
    before = Repo.all(from s in Game.Schema.Skill, where: s.current == true, select: s.id, order_by: s.id)
    season_uuid = Game.current_season().resource_uuid
    assert_raise Ecto.NoResultsError, fn -> Moba.Conductor.regenerate_resources!() end
    assert Repo.all(from s in Game.Schema.Skill, where: s.current == true, select: s.id, order_by: s.id) == before
    assert Game.current_season().resource_uuid == season_uuid
  end

  test "old guest accounts retain new or recently active training runs" do
    guest = Game.start_guest!("old-active-guest", base_avatar(), creation_skills())
    old = NaiveDateTime.utc_now() |> NaiveDateTime.add(-8 * 86400) |> NaiveDateTime.truncate(:second)
    Repo.update_all(from(p in Game.Schema.Player, where: p.id == ^guest.id), set: [inserted_at: old, updated_at: old])
    Moba.Cleaner.cleanup_old_records()
    assert Game.get_player!(guest.id).current_pve_hero_id == guest.current_pve_hero_id
    refute Game.get_hero!(guest.current_pve_hero_id).archived_at

    Repo.update_all(from(h in Game.Schema.Hero, where: h.id == ^guest.current_pve_hero_id),
      set: [inserted_at: old, updated_at: old]
    )

    Moba.Cleaner.cleanup_old_records()
    refute Game.get_player!(guest.id).current_pve_hero_id
    assert Game.get_hero!(guest.current_pve_hero_id).archived_at
  end

  test "daily ticks apply promotion, reset and streak changes once per interval" do
    player = create_player!(%{pvp_tier: 2, daily_wins: 100, total_matches: 1, pvp_points: 100_000})
    Game.update_season!(Game.current_season(), %{last_pvp_update_at: DateTime.add(DateTime.utc_now(), -86401)})
    Moba.Conductor.pvp_tick!()
    after_first = Game.get_player!(player.id)
    Moba.Conductor.pvp_tick!()
    after_second = Game.get_player!(player.id)
    assert after_first.current_immortal_streak == 1
    assert after_second.current_immortal_streak == 1
  end

  test "ranker coalesces repeated requests without delaying the scheduled refresh" do
    pid = start_supervised!({Moba.Ranker, name: __MODULE__})
    MobaWeb.subscribe("player-ranking")
    GenServer.cast(pid, :pvp)
    first = :sys.get_state(pid)

    for _ <- 1..100, do: GenServer.cast(pid, :pvp)
    assert :sys.get_state(pid) == first
    send(pid, {:update_pvp, first.token})
    assert %{token: nil, timer_ref: nil} = :sys.get_state(pid)
    assert_receive {"ranking", %{}}

    GenServer.cast(pid, :pvp)
    next = :sys.get_state(pid)
    send(pid, {:update_pvp, first.token})
    assert :sys.get_state(pid) == next
    refute_received {"ranking", %{}}
    send(pid, {:update_pvp, next.token})
    assert %{token: nil, timer_ref: nil} = :sys.get_state(pid)
    assert_receive {"ranking", %{}}
  end
end
