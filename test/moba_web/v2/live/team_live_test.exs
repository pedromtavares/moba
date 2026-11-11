defmodule MobaWeb.V2.TeamLiveTest do
  use MobaWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Moba.AccountsFixtures, only: [valid_user_attributes: 0]
  import Test.TeamHelper
  alias Moba.Repo
  alias Moba.Engine.Schema.Battle
  alias Moba.Game.{TeamRuns, TeamTraining, TrainingEncounters}
  alias Moba.Game.Schema.{Match, TeamEncounter, TrainingTeam}
  alias Moba.Game.Training.Snapshot

  setup %{conn: conn} do
    {scope, player} = team_account()
    conn = conn |> log_in_user(scope.user) |> put_session(:player_id, player.id)
    %{conn: conn, scope: scope, player: player}
  end

  test "Expert team training shares its refresh allowance and rerolls only the selected hero", %{conn: conn} do
    {scope, player} = team_account(4)
    conn = conn |> log_in_user(scope.user) |> put_session(:player_id, player.id)
    record = team_run(scope, player)
    {:ok, record} = TeamRuns.update(scope, record, &Map.delete(&1, :target_refreshes_used))
    before = TeamRuns.state(record)
    {:ok, view, _} = live(conn, "/training?run=#{record.id}")

    button = "#team-2-training-refresh-targets"
    assert has_element?(view, "#{button}[phx-value-hero_id='2']", "Refresh Targets 5")
    view |> element(button) |> render_click()

    after_refresh = TeamRuns.state(TeamRuns.get!(scope, record.id))
    assert length(after_refresh.targets[2]) == 3
    assert MapSet.disjoint?(MapSet.new(before.targets[2], & &1.id), MapSet.new(after_refresh.targets[2], & &1.id))
    assert Map.take(after_refresh.targets, [1, 3]) == Map.take(before.targets, [1, 3])
    assert after_refresh.turns_left == before.turns_left
    assert has_element?(view, "#training-refresh-targets", "Refresh Targets 4")
    assert has_element?(view, button, "Refresh Targets 4")

    for _ <- 1..4, do: view |> element(button) |> render_click()
    refute has_element?(view, "button[phx-click=refresh-targets]")
    exhausted = TeamRuns.state(TeamRuns.get!(scope, record.id))
    render_click(view, "refresh-targets", %{"hero_id" => "2"})
    assert TeamRuns.state(TeamRuns.get!(scope, record.id)) == exhausted
  end

  test "training still loads and starts battles with an unavailable historical replay", %{
    conn: conn,
    scope: scope,
    player: player
  } do
    record = team_run(scope, player)
    before = TeamRuns.state(record)
    orphan = Repo.insert!(%TeamEncounter{team_run_id: record.id, turn: 1, label: "Old target"})
    broken = Repo.insert!(%TeamEncounter{team_run_id: record.id, turn: 1, label: "Broken target"})

    Repo.insert!(%Battle{
      type: "training",
      training_team_id: record.id,
      training_encounter_id: broken.id,
      training_index: 1,
      training_state: <<131, 80, 0>>
    })

    {:ok, view, _} = live(conn, "/training?run=#{record.id}")
    assert has_element?(view, "#team-targets[data-hero='1']")
    render_click(view, "show-log")
    refute has_element?(view, "#team-replay-#{orphan.id}")
    refute has_element?(view, "#team-replay-#{broken.id}")
    assert TeamRuns.state(TeamRuns.get!(scope, record.id)).heroes == before.heroes

    view |> element("#gank-#{hd(before.targets[1]).id}") |> render_click()
    assert [encounter] = TeamRuns.encounters(scope, record.id)
    assert_redirect(view, TrainingEncounters.path(encounter, 1))
  end

  test "an unreadable run offers a way back to Base and a fresh draft", %{conn: conn, scope: scope, player: player} do
    record = team_run(scope, player)
    {:ok, draft} = TeamRuns.draft(scope, player)
    replace_snapshot(draft, :state, <<131, 80, 0>>)

    for bad_state <- [<<131, 80, 0>>, Snapshot.encode(%{phase: :playing})] do
      replace_snapshot(record, :state, bad_state)
      {:ok, view, _} = live(conn, "/training")
      assert has_element?(view, "#training-save-unavailable a[href='/base']")
      assert has_element?(view, "#training-save-unavailable a[href='/new']")
      assert Repo.get!(TrainingTeam, record.id).state == bad_state
      assert {:ok, _, _} = live(conn, "/base")
    end

    assert {:ok, _, _} = live(conn, "/new")
    {:ok, replacement} = TeamRuns.draft(scope, player)
    assert replacement.id != draft.id
    assert TeamRuns.state(replacement).picks == []
    assert Repo.get!(TrainingTeam, draft.id).archived_at
  end

  test "a corrupted pending battle opens a recovery link and training rebuilds the same battle", %{
    conn: conn,
    scope: scope,
    player: player
  } do
    record = team_run(scope, player)

    {:ok, record} =
      TeamRuns.update(scope, record, fn run ->
        run |> TeamTraining.battle(hd(run.targets[1]).id) |> then(&TeamTraining.battle_action(scope, &1, %{auto: true}))
      end)

    before = TeamRuns.state(record)
    encounter = TeamTraining.active_encounter(before)
    [battle_id] = encounter.battle_ids
    replace_snapshot(Repo.get!(Battle, battle_id), :training_state, Snapshot.encode(%{}))
    path = TrainingEncounters.path(encounter, 1)

    {:ok, replay, _} = live(conn, path)
    assert has_element?(replay, "#training-replay-unavailable a[href='/training?run=#{record.id}']")

    {:ok, training, _} = live(conn, "/training")
    assert has_element?(training, "#team-resume[href='#{path}']")
    assert TeamRuns.get!(scope, record.id) |> TeamRuns.state() == before
    {:ok, restored, _} = live(conn, path)
    assert has_element?(restored, "#combat-stage")
  end

  test "training rebuilds a deleted pending encounter and resumes through the new URL", %{
    conn: conn,
    scope: scope,
    player: player
  } do
    record = team_run(scope, player)
    {:ok, record} = TeamRuns.update(scope, record, fn run -> TeamTraining.battle(run, hd(run.targets[1]).id) end)
    before = TeamRuns.state(record)
    missing = TeamTraining.active_encounter(before)
    Repo.delete!(Repo.get!(TeamEncounter, missing.id))

    {:ok, view, _} = live(conn, "/training")
    after_repair = TeamRuns.state(TeamRuns.get!(scope, record.id))
    [restored] = TeamRuns.encounters(scope, record.id)
    assert restored.id != missing.id
    assert Map.drop(after_repair, [:encounters]) == Map.drop(before, [:encounters])
    path = TrainingEncounters.path(restored, 1)
    assert has_element?(view, "#team-resume[href='#{path}']")
    assert {:ok, _, _} = live(conn, path)

    {:ok, refreshed, _} = live(conn, "/training")
    assert has_element?(refreshed, "#team-resume[href='#{path}']")
    assert [^restored] = TeamRuns.encounters(scope, record.id)
  end

  test "training rebuilds the missing battle of a pending league match", %{conn: conn, scope: scope, player: player} do
    record = team_run(scope, player)
    {:ok, record} = TeamRuns.update(scope, record, &TeamTraining.league(%{&1 | turns_left: 0}))
    before = TeamRuns.state(record)
    pending = TeamTraining.active_encounter(before)
    match = Repo.get!(Match, pending.match_id)
    [old_id] = pending.battle_ids
    Repo.delete!(Repo.get!(Battle, old_id))

    {:ok, view, _} = live(conn, "/training")
    [restored] = TeamRuns.encounters(scope, record.id)
    assert restored.match_id == match.id
    assert restored.battle_ids != [old_id]
    path = TrainingEncounters.path(restored, 1)
    assert has_element?(view, "#team-resume[href='#{path}']")
    assert {:ok, _, _} = live(conn, path)
  end

  defp replace_snapshot(record, field, binary) do
    record |> Ecto.Changeset.change(%{field => binary}) |> Repo.update!()
  end

  test "registered players use the shared name input and their team name survives creation", %{
    conn: conn,
    scope: scope,
    player: player
  } do
    {:ok, view, _} = live(conn, "/new")
    assert has_element?(view, "#team-draft-launch .creation-name-field label", "Team name")
    assert has_element?(view, "#team-draft-launch .creation-name-field--inline")
    assert has_element?(view, "#team_name.invoke-name-input[value='#{scope.user.username}']")
    refute has_element?(view, "#invoke-name-form")

    data =
      view
      |> element("#invoke-modern")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-creation]")
      |> LazyHTML.attribute("data-creation")
      |> hd()
      |> Jason.decode!()

    refute data["named"]

    roster = Jason.encode!(team_picks(scope))
    {:ok, draft} = TeamRuns.draft(scope, player)

    for invalid <- ["  ", String.duplicate("a", 31)] do
      view |> form("#team-draft-launch", team: %{name: invalid}) |> render_submit(%{roster: roster})
      assert has_element?(view, "#team-name-error[role=alert]", "3–30 characters")
      assert has_element?(view, "#team_name[aria-invalid=true]")
      assert TeamRuns.get!(scope, draft.id).phase == "draft"
      assert TeamRuns.state(TeamRuns.get!(scope, draft.id)).picks == []
    end

    view |> form("#team-draft-launch", team: %{name: "  Midnight Order  "}) |> render_submit(%{roster: roster})
    assert_redirect(view, "/training")
    record = TeamRuns.get!(scope, draft.id)
    assert record.name == "Midnight Order"
    assert TeamRuns.state(record).name == "Midnight Order"
    assert record.phase == "playing"
    assert Enum.all?(TeamTraining.team(TeamRuns.state(record)), &(&1.hero.name == "Midnight Order"))

    {:ok, base, _} = live(conn, "/base")
    assert has_element?(base, "#visible-team-#{record.id} .hero-card-name", "Midnight Order")
    {:ok, record} = TeamRuns.update(scope, record, &%{&1 | phase: :finished})
    entry = Enum.find(TeamRuns.ranking(record.id), &(&1.team.id == record.id))
    assert entry.team.name == "Midnight Order"
    assert Enum.all?(Game.get_heroes(record.hero_ids), &(&1.name == "Midnight Order"))
  end

  test "guests see neither name input and cannot submit a custom team name" do
    guest = TeamRuns.start_guest!("name-guest-#{System.unique_integer([:positive])}", hd(team_picks(%{user: nil})))
    scope = TeamRuns.scope(guest)
    {:ok, record} = TeamRuns.draft(scope, guest)

    {:ok, view, _} = live(build_conn() |> init_test_session(player_id: guest.id), "/new")
    refute has_element?(view, "#team_name, #invoke-name-form")

    render_submit(view, "begin-training", %{
      "roster" => Jason.encode!(team_picks(scope)),
      "team" => %{"name" => "Guest override"}
    })

    assert_redirect(view, "/training")
    record = TeamRuns.get!(scope, record.id)
    assert record.name == nil
    assert TeamRuns.state(record).name == nil
    assert Enum.all?(TeamTraining.team(TeamRuns.state(record)), &(&1.hero.name == &1.hero.avatar.name))
  end

  test "team routes accept accounts and guests but still require a player session", %{conn: conn} do
    assert redirected_to(get(build_conn(), "/new")) in ["/start", "/users/log_in"]
    player = create_player!() |> then(&Game.get_player!(&1.id))
    regular = build_conn() |> log_in_user(player.user) |> put_session(:player_id, player.id)
    assert {:ok, _, _} = live(regular, "/new")
    assert {:error, {:live_redirect, %{to: "/base"}}} = live(regular, "/training")
    assert {:ok, _, _} = live(conn, "/new")
  end

  test "training selects the active team and preserves explicit solo access", %{
    conn: conn,
    scope: scope,
    player: player
  } do
    pick = hd(team_picks(scope))
    {:ok, solo} = Game.Training.invoke_hero(player, %{name: "Solo hero"}, pick["avatar"], pick["skills"])
    record = team_run(scope, player)
    {:ok, team, _} = live(conn, "/training")
    assert has_element?(team, "#team-training-page")
    {:ok, individual, _} = live(conn, "/training?solo=true")
    refute has_element?(individual, "#team-training-page")
    assert has_element?(individual, "#hero-bar")
    assert Game.get_player!(player.id).current_pve_hero_id == solo.id
    assert TeamRuns.state(TeamRuns.get!(scope, record.id)).phase == :playing
  end

  test "guests can use canonical training battle URLs without an account token" do
    guest = TeamRuns.start_guest!("canonical-#{System.unique_integer([:positive])}", hd(team_picks(%{user: nil})))
    scope = TeamRuns.scope(guest)
    {:ok, record} = TeamRuns.draft(scope, guest)

    for pick <- tl(team_picks(scope)) do
      current = TeamRuns.get!(scope, record.id)
      {:ok, _} = TeamRuns.update(scope, current, &TeamTraining.add_pick(scope, &1, pick))
    end

    record = TeamRuns.get!(scope, record.id)
    {:ok, record} = TeamRuns.update(scope, record, &TeamTraining.begin_run/1)
    guest_conn = build_conn() |> init_test_session(player_id: guest.id)
    {:ok, view, _} = live(guest_conn, "/training")
    assert has_element?(view, "#team-training-page")

    assert has_element?(
             view,
             "#training-ascent a#training-guest-sign-in[href='/users/log_in']",
             "Already registered? Sign in"
           )

    for unit <- TeamTraining.team(TeamRuns.state(record)) do
      selector = "#team-hero-panel-#{unit.id} .hud-identity .hero-name"
      assert has_element?(view, selector, unit.hero.avatar.name)
      refute has_element?(view, selector, "Guest #")
    end

    {:ok, record} =
      TeamRuns.update(scope, record, fn run ->
        run = run |> put_in([:heroes, 1, :hero, Access.key(:name)], "Guest ##{guest.id}") |> easy_target()
        TeamTraining.battle(run, hd(run.targets[1]).id)
      end)

    encounter = TeamTraining.active_encounter(TeamRuns.state(record))
    path = TrainingEncounters.path(encounter, 1)
    {:ok, battle, _} = live(guest_conn, path)
    assert has_element?(battle, "#team-battle-page")
    avatar = TeamTraining.team(TeamRuns.state(record)) |> hd() |> then(& &1.hero.avatar.name)
    assert has_element?(battle, ".stage-left [data-unit-name]", avatar)
    assert has_element?(battle, ".stage-left .stage-unit-level", "Level 1")
    refute has_element?(battle, ".stage-left .stage-unit-level", avatar)

    {:ok, _} = TeamRuns.update(scope, record, &finish_team(&1, scope))
    {:ok, result, _} = live(guest_conn, path)
    assert has_element?(result, "[data-stage-result-title]", "You Win")
    assert has_element?(result, ".stage-left [data-unit-name]", avatar)
    assert has_element?(result, ".combat-turn-actor", avatar)
    refute render(result) =~ "Guest ##{guest.id}"

    user = Test.AccountsHelper.create_user()
    Moba.after_registration(user, guest.id)
    conn = build_conn() |> log_in_user(user) |> put_session(:player_id, guest.id)
    {:ok, claimed_replay, _} = live(conn, path)
    assert has_element?(claimed_replay, ".stage-left [data-unit-name]", user.username)
    assert has_element?(claimed_replay, ".combat-turn-actor", user.username)
    assert has_element?(claimed_replay, ".stage-right [data-unit-name]", hd(encounter.dire).hero.name)
    refute render(claimed_replay) =~ "Guest ##{guest.id}"
  end

  test "draft accepts and persists the roster only on Begin Training", %{
    conn: conn,
    scope: scope,
    player: player
  } do
    count = Moba.Repo.aggregate(Game.Schema.Hero, :count)
    {:ok, view, _} = live(conn, "/new")
    assert has_element?(view, "#invoke-modern[phx-hook=InvokeStage]")
    assert has_element?(view, "#create-button", "Add to roster")
    assert has_element?(view, "#team-draft-begin[disabled]")
    {:ok, draft} = TeamRuns.draft(scope, player)

    assert has_element?(view, "#training-mode a[href='/new/solo']", "Solo 1v1")

    [first | _] = picks = team_picks(scope)
    render_hook(view, "create", first)
    render_click(view, "remove-pick", %{"index" => "0"})
    assert TeamRuns.get!(scope, draft.id).lock_version == draft.lock_version
    assert TeamRuns.state(TeamRuns.get!(scope, draft.id)).picks == []

    for invalid <- ["malformed", Jason.encode!([first]), Jason.encode!([first, first, first])] do
      view |> form("#team-draft-launch") |> render_submit(%{roster: invalid})
      assert has_element?(view, "#game-feedback-error", "Choose three different unlocked avatars and valid builds.")
      assert TeamRuns.get!(scope, draft.id).lock_version == draft.lock_version
    end

    view |> form("#team-draft-launch") |> render_submit(%{roster: Jason.encode!(picks)})
    assert_redirect(view, "/training")

    assert Enum.map(TeamRuns.state(TeamRuns.get!(scope, draft.id)).picks, &to_string(&1.avatar.id)) ==
             Enum.map(picks, &to_string(&1["avatar"]))

    assert Moba.Repo.aggregate(Game.Schema.Hero, :count) == count
    assert TeamRuns.state(TeamRuns.latest(scope, player.id)).phase == :playing
  end

  test "shop visibility is shared by every preloaded hero and survives hero actions", %{
    conn: conn,
    scope: scope,
    player: player
  } do
    record = team_run(scope, player)
    {:ok, view, _} = live(conn, "/training")
    ids = ["shop-modal", "team-2-shop-modal", "team-3-shop-modal"]
    for id <- ids, do: assert(has_element?(view, "##{id}.d-none"))
    view |> element("#toggle-shop") |> render_click()
    for id <- ids, do: assert(has_element?(view, "##{id}.d-block"))
    assert TeamRuns.get!(scope, record.id).lock_version == record.lock_version

    view |> element("#team-2-team-auto-buy") |> render_click()
    for id <- ids, do: assert(has_element?(view, "##{id}.d-block"))
    assert has_element?(view, "#team-2-team-auto-buy[aria-checked=false]")
    view |> element("#team-2-close-button") |> render_click()
    for id <- ids, do: assert(has_element?(view, "##{id}.d-none"))
    view |> element("#team-3-toggle-shop") |> render_click()
    for id <- ids, do: assert(has_element?(view, "##{id}.d-block"))

    item = TeamRuns.state(record).heroes[2].hero.items |> List.first()
    view |> element("#team-2-close-button") |> render_click()
    view |> element("#team-2-inventory-#{item.id}") |> render_click()
    for id <- ids, do: assert(has_element?(view, "##{id}.d-block"))
    assert has_element?(view, "#team-2-shop-detail-name", item.name)
    assert has_element?(view, "#team-2-sell-#{item.id}")
  end

  test "all hero views and target artwork preload, and switching uses only client commands", %{
    conn: conn,
    scope: scope,
    player: player
  } do
    record = team_run(scope, player)
    before = TeamRuns.state(record)
    {:ok, view, _} = live(conn, "/training")
    assert has_element?(view, "#team-targets[data-hero='1']")
    assert has_element?(view, "#team-hero-selector #team-select-1[aria-pressed=true]")
    assert has_element?(view, "#hero-team-tabs #team-hero-selector[role=tablist]")
    assert has_element?(view, "#hero-team-tabs")
    assert has_element?(view, "#team-hero-panel-1:not(.d-none) #hero-bar")
    assert has_element?(view, "#team-hero-panel-2.d-none #team-2-hero-bar")
    assert has_element?(view, "#team-hero-panel-3.d-none #team-3-hero-bar")
    assert has_element?(view, "#team-select-1[aria-keyshortcuts='1']")
    assert has_element?(view, "#team-select-2[aria-keyshortcuts='2']")
    assert has_element?(view, "#team-select-3[aria-keyshortcuts='3']")
    assert has_element?(view, "#training-controls-hint", "to move between targets")
    assert has_element?(view, "#toggle-shop[aria-keyshortcuts=F]")
    assert has_element?(view, "#shop-modal[phx-hook=ShopKeyboard] [data-close-on-escape]")
    refute has_element?(view, "#hero-bar #team-hero-selector")
    refute has_element?(view, "#show-farm-tabs")
    refute has_element?(view, ".farm-tabs, #farm-tab-meditation, #farm-tab-mine")
    assert has_element?(view, "#team-reward-mode[role=switch][aria-checked=false][phx-value-mode=focus]")
    assert has_element?(view, "#team-reward-mode .is-active .ui-users")

    reward_tooltip =
      "Shared rewards will equally distribute all rewards gained from training battles. Focus rewards will reward only the hero who engaged. League challenge rewards remain equally split always."

    assert has_element?(view, "#team-reward-mode[data-toggle=tooltip][title='#{reward_tooltip}']")

    assert has_element?(
             view,
             "#team-auto-buy[title*='items you buy or transmute yourself are protected']",
             "AUTO"
           )

    assert Enum.count(view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query("#team-targets .training-target")) ==
             3

    for id <- before.order do
      commands =
        view
        |> element("#team-select-#{id}")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("button")
        |> LazyHTML.attribute("phx-click")
        |> hd()
        |> Jason.decode!()

      refute Enum.any?(commands, fn [command, _] -> command in ["push", "patch", "redirect"] end)

      assert Enum.any?(commands, fn [command, options] ->
               command == "remove_class" && options["to"] == "#team-hero-panel-#{id}"
             end)

      assert has_element?(view, "#team-hero-panel-#{id} [data-hero-id='#{id}']")

      for target <- before.targets[id] do
        assert has_element?(view, "#team-hero-panel-#{id} #gank-#{target.id}[phx-value-hero_id='#{id}']")

        assert has_element?(
                 view,
                 "link[rel=preload][as=image][href='#{MobaWeb.V2.Components.GameHelpers.background_url(target.defender.avatar)}']"
               )
      end
    end

    ids = view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query("[id]") |> LazyHTML.attribute("id")
    assert ids == Enum.uniq(ids)
    assert TeamRuns.get!(scope, record.id).lock_version == record.lock_version
    assert has_element?(view, "#team-2-hero-inventory[data-hero-id='2']")
    view |> element("#team-2-team-reward-mode") |> render_click()
    assert has_element?(view, "#team-2-team-reward-mode[aria-checked=true][phx-value-mode=shared]")
    assert has_element?(view, "#team-2-team-reward-mode .is-active .ui-helmet")
    assert has_element?(view, "#team-2-team-reward-mode[title='#{reward_tooltip}']")
    view |> element("#team-2-team-reward-mode") |> render_click()
    assert has_element?(view, "#team-2-team-reward-mode[aria-checked=false]")
    view |> element("#team-2-team-reward-mode") |> render_click()
    view |> element("#team-2-team-auto-buy") |> render_click()
    assert has_element?(view, "#team-2-team-auto-buy[aria-checked=false]")
    view |> element("#team-2-team-mobile-auto-buy") |> render_click()
    assert has_element?(view, "#team-2-team-auto-buy[aria-checked=true]")
    view |> element("#team-2-team-mobile-auto-buy") |> render_click()
    view |> element("#team-2-toggle-shop") |> render_click()
    assert has_element?(view, "#team-2-shop")
    view |> element("#team-2-close-button") |> render_click()
    assert has_element?(view, "#team-2-shop-modal.d-none")
    saved = TeamRuns.state(TeamRuns.get!(scope, record.id))
    assert saved.selected == 2
    assert saved.reward_mode == :focus
    refute saved.heroes[2].auto_buy
    assert saved.heroes[1].auto_buy
    assert saved.targets == before.targets
    for target <- before.targets[1], do: assert(has_element?(view, "#gank-#{target.id}"))
  end

  test "actions use their explicit hero after a frontend switch and reject invalid hero IDs", %{
    conn: conn,
    scope: scope,
    player: player
  } do
    record = team_run(scope, player)

    {:ok, record} =
      TeamRuns.update(scope, record, fn run ->
        update_in(run.heroes[2], fn h -> %{h | hero: %{h.hero | skill_levels_available: 1, level: 3}} end)
      end)

    before = TeamRuns.state(record)
    {:ok, view, _} = live(conn, "/training")
    view |> element("#team-2-hero-bar [data-hud-skill-index='0'] .hud-upgrade") |> render_click()
    saved_record = TeamRuns.get!(scope, record.id)
    saved = TeamRuns.state(saved_record)
    assert saved.selected == 2
    assert saved.heroes[2].hero.skill_levels_available == 0
    assert saved.heroes[1] == before.heroes[1]
    assert saved.targets == before.targets
    render_click(view, "auto-buy", %{"hero_id" => "999"})
    assert TeamRuns.get!(scope, record.id).lock_version == saved_record.lock_version
    target = hd(saved.targets[3])
    view |> element("#gank-#{target.id}") |> render_click()
    [encounter] = TeamRuns.encounters(scope, record.id)
    assert_redirect(view, TrainingEncounters.path(encounter, 1))
    run = TeamRuns.state(TeamRuns.get!(scope, record.id))
    assert TeamTraining.active_encounter(run).radiant |> hd() |> Map.fetch!(:id) == 3
  end

  test "team training shows how many heroes remain before the next league challenge", %{
    conn: conn,
    scope: scope,
    player: player
  } do
    record = team_run(scope, player)

    for {turns, prompt} <- [{5, "Battle 5 heroes to challenge Gold"}, {1, "Battle 1 hero to challenge Gold"}] do
      {:ok, record} =
        TeamRuns.update(scope, TeamRuns.get!(scope, record.id), fn run ->
          heroes =
            Map.new(run.heroes, fn {id, h} ->
              {id, %{h | hero: %{h.hero | league_tier: 1, pve_current_turns: turns}}}
            end)

          %{run | league_tier: 1, turns_left: turns, heroes: heroes}
        end)

      {:ok, view, _} = live(conn, "/training?run=#{record.id}")
      assert has_element?(view, "#training-ascent[data-league='2'] #training-ascent-status", prompt)
      assert has_element?(view, "#training-ascent-status .ascent-status-league", "Gold")
    end
  end

  test "team training omits farming tabs even when the player's farm preference is enabled", %{
    conn: conn,
    scope: scope,
    player: player
  } do
    player = player |> Ecto.Changeset.change(preferences: %{show_farm_tabs: true}) |> Moba.Repo.update!()
    record = team_run(scope, player)

    {:ok, record} =
      TeamRuns.update(scope, record, fn run ->
        heroes = Map.new(run.heroes, fn {id, h} -> {id, %{h | hero: %{h.hero | pve_current_turns: 0}}} end)
        %{run | turns_left: 0, heroes: heroes}
      end)

    {:ok, view, _} = live(conn, "/training?run=#{record.id}")
    refute has_element?(view, ".farm-tabs, #show-farm-tabs, #farm-tab-meditation, #farm-tab-mine")
    assert has_element?(view, "#league-challenge-intro", "Win a 3v3 team fight to rank up.")
    view |> element("#start-league-challenge") |> render_click()
    [encounter] = TeamRuns.encounters(scope, record.id)
    assert_redirect(view, TrainingEncounters.path(encounter, 1))
    pending = TeamRuns.state(TeamRuns.get!(scope, record.id))
    e = TeamTraining.active_encounter(pending)
    assert length(e.radiant) == 3
    assert length(e.dire) == 3
    {:ok, battle, _} = live(conn, TrainingEncounters.path(encounter, 1))
    assert has_element?(battle, "#training-auto-match[aria-keyshortcuts=G]", "Auto all battles")
    assert has_element?(battle, "#training-auto-match .battle-auto-forward .ui-play")
    assert has_element?(battle, "#training-auto-match kbd", "G")
    battle |> element("#training-auto-battle") |> render_click()

    assert has_element?(
             battle,
             "#training-auto-battle[phx-click=pause][aria-pressed=true][aria-keyshortcuts=T]",
             "Pause"
           )

    assert has_element?(battle, "#training-auto-battle .battle-auto-pause")
    refute has_element?(battle, "#training-pause-playback")
    battle |> element("#training-auto-battle") |> render_click()
    assert has_element?(battle, "#training-auto-battle[phx-click=auto-battle][aria-pressed=false]", "Auto battle")
    battle |> element("#training-auto-match") |> render_click()

    assert has_element?(
             battle,
             "#training-auto-match[phx-click=pause][aria-pressed=true][aria-keyshortcuts=G]",
             "Pause"
           )

    assert has_element?(battle, "#training-auto-match .battle-auto-pause")
    refute has_element?(battle, "#training-pause-playback")
    battle |> element("#training-auto-match") |> render_click()
    assert has_element?(battle, "#training-auto-match[phx-click=auto-match][aria-pressed=false]", "Auto all battles")
  end

  test "league challenges require every hero's skill points and guide the pending hero", %{
    conn: conn,
    scope: scope,
    player: player
  } do
    record = team_run(scope, player)

    {:ok, record} =
      TeamRuns.update(scope, record, fn run ->
        heroes =
          Map.new(run.heroes, fn {id, h} ->
            {id,
             %{
               h
               | hero: %{h.hero | pve_current_turns: 0, level: 3, skill_levels_available: if(id == 2, do: 1, else: 0)}
             }}
          end)

        %{run | turns_left: 0, heroes: heroes}
      end)

    {:ok, view, _} = live(conn, "/training")
    assert has_element?(view, "#start-league-challenge[disabled][aria-describedby=league-skill-warning]")

    assert has_element?(
             view,
             "button#league-skill-warning[aria-keyshortcuts=Space]",
             "Spend all skill points to begin."
           )

    assert has_element?(view, "#league-skill-warning kbd", "SPACE")

    guide_action =
      view
      |> element("#league-skill-warning")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#league-skill-warning")
      |> LazyHTML.attribute("phx-click")
      |> hd()
      |> Jason.decode!()

    assert Enum.any?(
             guide_action,
             &match?(["remove_class", %{"to" => "#team-hero-panel-2", "names" => ["d-none"]}], &1)
           )

    refute has_element?(view, ".skill-guidance-arrow, #team-hero-panel-1.has-pending-skill-points")
    assert has_element?(view, "#team-hero-panel-2.has-pending-skill-points")
    render_click(view, "league", %{"hero_id" => "1"})
    assert TeamRuns.encounters(scope, record.id) == []
    view |> element("#team-2-hero-bar [data-hud-skill-index='0'] .hud-upgrade") |> render_click()
    assert TeamTraining.pending_skill_heroes(TeamRuns.state(TeamRuns.get!(scope, record.id))) == []
    refute has_element?(view, ".skill-guidance-arrow, .league-skill-warning")
    assert has_element?(view, "#start-league-challenge:not([disabled])")
    view |> element("#team-2-start-league-challenge") |> render_click()
    [encounter] = TeamRuns.encounters(scope, record.id)
    assert_redirect(view, TrainingEncounters.path(encounter, 1))
  end

  test "reward tooltips distinguish total spoils from the shared or focused payout", %{
    conn: conn,
    scope: scope,
    player: player
  } do
    record = team_run(scope, player)
    target = TeamRuns.state(record).targets[1] |> Enum.find(&(&1.difficulty == "strong"))
    {:ok, view, _} = live(conn, "/training")

    tooltip = fn ->
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#target-rewards-#{target.id}")
      |> LazyHTML.attribute("title")
      |> hd()
      |> LazyHTML.from_fragment()
    end

    shared = tooltip.()
    assert LazyHTML.query(shared, "header") |> LazyHTML.text() =~ "Total spoils"
    assert LazyHTML.query(shared, "[data-reward=gold] dd") |> LazyHTML.text() == "+1800"
    assert LazyHTML.query(shared, "[data-reward=xp] dd") |> LazyHTML.text() == "+1800"

    assert LazyHTML.query(shared, "[data-reward-allocation=shared]") |> LazyHTML.text() =~
             "Each hero: +600 Gold and +600 XP"

    view |> element("#team-reward-mode") |> render_click()
    focused = tooltip.()

    assert LazyHTML.query(focused, "[data-reward-allocation=focus]") |> LazyHTML.text() =~
             "Fighting hero: +1800 Gold and +1800 XP"
  end

  test "farming opens the identical manual battle UI with auto controls, then returns rewards to the team", %{
    conn: conn,
    scope: scope,
    player: player
  } do
    record = team_run(scope, player)
    {:ok, record} = TeamRuns.update(scope, record, &easy_target/1)
    before = TeamRuns.state(record)
    target = hd(before.targets[1])
    {:ok, view, _} = live(conn, "/training")
    render_click(view, "battle", %{"id" => hd(before.targets[2]).id})
    assert TeamRuns.state(TeamRuns.get!(scope, record.id)).phase == :playing
    view |> element("#gank-#{target.id}") |> render_click()
    [encounter] = TeamRuns.encounters(scope, record.id)
    path = TrainingEncounters.path(encounter, 1)
    assert_redirect(view, path)
    {:ok, battle, _} = live(conn, path)
    assert has_element?(battle, "#battle-page #combat-stage")
    assert has_element?(battle, "#battle-bar #attack-button")
    assert has_element?(battle, "#combat-stage #combat-log-toggle")

    assert has_element?(
             battle,
             ".combat-stage-shell .stage-automation #training-auto-battle[aria-keyshortcuts=T]",
             "Auto battle"
           )

    assert has_element?(battle, "#training-auto-battle .ui-play")
    assert has_element?(battle, "#training-auto-battle kbd", "T")
    assert has_element?(battle, "#training-play-controls[phx-hook=BattleAutoHotkeys]")
    refute has_element?(battle, "#battle-bar #training-play-controls, #training-auto-match")
    refute has_element?(battle, "#training-pause-playback")
    assert has_element?(battle, "#training-return[href='/training?run=#{record.id}']", "Return to training")

    battle
    |> element("#combat-stage")
    |> render_hook("next-turn", %{"hero_id" => "1", "skill_id" => "", "item_id" => ""})

    saved = TeamRuns.state(TeamRuns.get!(scope, record.id))
    assert saved.phase == :playing

    for id <- before.order do
      previous_ids = Enum.map(before.targets[id], & &1.id)
      refute Enum.any?(saved.targets[id], &(&1.id in previous_ids))
    end

    assert has_element?(battle, "#training-battle-result[data-result=victory]")
    assert has_element?(battle, "#training-battle-result .team-result-spoils", "+#{target.reward} Gold")
    assert has_element?(battle, "#training-battle-result .team-result-spoils", "+#{target.reward} XP")
    refute has_element?(battle, "#training-battle-result .league-outcome-eyebrow")
    refute has_element?(battle, "#training-battle-result .team-result-spoils small")

    refute has_element?(
             battle,
             "#training-battle-result .league-stage-cleared, #training-battle-result .league-outcome-description"
           )

    refute has_element?(battle, "#training-battle-result .team-opponent-steps")
    assert has_element?(battle, "#training-continue[href='/training?run=#{record.id}']", "Continue training")
    refute has_element?(battle, "#training-auto-battle")
    {:ok, returned, _} = live(conn, "/training?run=#{record.id}")
    refute has_element?(returned, "#team-last-result")
    assert has_element?(returned, "#team-targets")
    assert saved.heroes[2].hero.total_gold_farm > 0
    for target <- saved.targets[2], do: assert(has_element?(returned, "#gank-#{target.id}"))
    for target <- before.targets[2], do: refute(has_element?(returned, "#gank-#{target.id}"))
  end

  test "capped battle results display only rewards actually credited", %{conn: conn, scope: scope, player: player} do
    for gold_room <- [100, 0] do
      record = team_run(scope, player)

      {:ok, record} =
        TeamRuns.update(scope, record, fn run ->
          heroes =
            Map.new(run.heroes, fn {id, unit} ->
              gold = 30_000 - if(id == 1, do: gold_room, else: 0)
              unit = Game.Training.Loadouts.grant_farm(%{unit | auto_buy: false}, gold, 37_700, run.catalog)
              {id, put_in(unit.hero.skill_levels_available, 0)}
            end)

          %{run | heroes: heroes, goal: 1}
          |> TeamTraining.league()
          |> simple_league()
          |> finish_team(scope)
        end)

      [encounter] = TeamRuns.encounters(scope, record.id)
      {:ok, view, _} = live(conn, TrainingEncounters.path(encounter, 3))
      assert has_element?(view, "#training-battle-result[data-result=victory]")
      assert has_element?(view, "#training-continue[href='/teams/#{record.id}']", "View team")
      refute has_element?(view, "#training-battle-result .team-result-spoils .text-info")

      if gold_room > 0 do
        assert has_element?(view, "#training-battle-result .team-result-spoils .text-warning", "+100 Gold")
      else
        refute has_element?(view, "#training-battle-result .team-result-spoils")
      end
    end
  end

  test "maxed heroes cannot battle targets in either reward mode and a maxed roster can challenge its league", %{
    conn: conn,
    scope: scope,
    player: player
  } do
    record = team_run(scope, player)

    {:ok, record} =
      TeamRuns.update(scope, record, fn run ->
        run
        |> TeamTraining.reward_mode(:focus)
        |> then(&put_in(&1.heroes[1].hero.level, 30))
        |> then(&put_in(&1.heroes[2].hero.level, 30))
      end)

    run = TeamRuns.state(record)
    target_id = hd(run.targets[1]).id
    {:ok, view, _} = live(conn, "/training")

    assert has_element?(view, "#team-select-1 .team-tab-max", "MAX")
    assert has_element?(view, "#team-hero-panel-1 .hud-experience[aria-valuenow='100']", "MAX")
    assert has_element?(view, "#team-max-level-panel", "can only fight in league challenges")
    assert has_element?(view, "#max-level-hero-arrow-1[data-max-guide-to='3']")
    assert has_element?(view, "#team-3-team-targets")
    refute has_element?(view, "#team-targets, #training-controls-hint")

    render_click(view, "battle", %{"id" => to_string(target_id), "hero_id" => "1"})
    assert TeamRuns.encounters(scope, record.id) == []
    assert TeamRuns.state(TeamRuns.get!(scope, record.id)).turns_left == run.turns_left

    view |> element("#team-reward-mode") |> render_click()
    assert has_element?(view, "#team-reward-mode[aria-checked=false]")
    assert has_element?(view, "#team-max-level-panel", "can only fight in league challenges")
    assert has_element?(view, "#max-level-hero-arrow-1[data-max-guide-to='3']")
    refute has_element?(view, "#team-targets")
    render_click(view, "battle", %{"id" => to_string(target_id), "hero_id" => "1"})
    assert TeamRuns.encounters(scope, record.id) == []
    assert TeamRuns.state(TeamRuns.get!(scope, record.id)).turns_left == run.turns_left
    refute has_element?(view, "#start-league-challenge")

    {:ok, _} =
      TeamRuns.update(scope, TeamRuns.get!(scope, record.id), fn run ->
        put_in(run.heroes[3].hero.level, 30)
      end)

    {:ok, view, _} = live(conn, "/training")
    refute has_element?(view, "#max-level-hero-arrow-1")
    assert has_element?(view, "#training-ascent-status", "challenge unlocked")
    view |> element("#start-league-challenge") |> render_click()
    [encounter] = TeamRuns.encounters(scope, record.id)
    assert_redirect(view, TrainingEncounters.path(encounter, 1))
  end

  test "manual team controls keep the same hero and layout while the opponent resolves", %{
    conn: conn,
    scope: scope,
    player: player
  } do
    record = team_run(scope, player)

    {:ok, record} =
      TeamRuns.update(scope, record, fn run ->
        target = hd(run.targets[1])
        opponent = simple_unit(target.opponent, 5000, 1)
        hero = simple_unit(run.heroes[1], 5000, 10)
        run = put_in(run.heroes[1], %{hero | hero: %{hero.hero | speed: 100, item_speed: 0}})
        run = put_in(run.targets[1], [%{target | opponent: opponent, defender: opponent.hero} | tl(run.targets[1])])
        TeamTraining.battle(run, target.id)
      end)

    e = TeamTraining.active_encounter(TeamRuns.state(record))
    {:ok, view, _} = live(conn, TrainingEncounters.path(e, 1))
    assert has_element?(view, "#battle-bar #attack-button[data-hero='1']:not([disabled])")
    view |> element("#combat-stage") |> render_hook("next-turn", %{"hero_id" => "1", "skill_id" => "", "item_id" => ""})

    assert has_element?(
             view,
             "#battle-bar .battle-active-turn[aria-busy=true][inert] #attack-button[data-hero='1'][disabled]"
           )

    refute has_element?(view, ".battle-passive-turn")

    scene =
      view
      |> element("#combat-stage")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#combat-stage")
      |> LazyHTML.attribute("data-scene")
      |> hd()
      |> Jason.decode!()

    view
    |> element("#combat-stage")
    |> render_hook("training-playback-ready", %{"frame" => scene["trainingPlayback"]["frame"]})

    assert has_element?(
             view,
             "#battle-bar .battle-active-turn[aria-busy=false] #attack-button[data-hero='1']:not([disabled])"
           )

    refute has_element?(view, ".battle-passive-turn")
  end

  test "a slower team hero waits for the target's opening and retains its own controls", %{
    conn: conn,
    scope: scope,
    player: player
  } do
    record = team_run(scope, player)

    {:ok, record} =
      TeamRuns.update(scope, record, fn run ->
        run = easy_target(run)
        run = put_in(run.heroes[1].hero, %{run.heroes[1].hero | speed: 0, item_speed: 0, pve_tier: 2})
        TeamTraining.battle(run, hd(run.targets[1]).id)
      end)

    e = TeamTraining.active_encounter(TeamRuns.state(record))
    assert e.initiator == :dire
    {:ok, view, _} = live(conn, TrainingEncounters.path(e, 1))
    assert has_element?(view, "#attack-button[data-hero='1'][disabled]")

    frame = fn ->
      view
      |> element("#combat-stage")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#combat-stage")
      |> LazyHTML.attribute("data-scene")
      |> hd()
      |> Jason.decode!()
      |> get_in(["trainingPlayback", "frame"])
    end

    view |> element("#combat-stage") |> render_hook("training-playback-ready", %{"frame" => frame.()})
    saved = TeamRuns.state(TeamRuns.get!(scope, record.id)) |> TeamTraining.active_encounter()
    assert hd(hd(saved.battles).turns).attacker.hero_id == hd(e.dire).id
    view |> element("#combat-stage") |> render_hook("training-playback-ready", %{"frame" => frame.()})
    assert has_element?(view, "#attack-button[data-hero='1']:not([disabled])")
  end

  test "a silenced training hero uses a basic attack with auto battle off", %{conn: conn, scope: scope, player: player} do
    record = team_run(scope, player)

    {:ok, record} =
      TeamRuns.update(scope, record, fn run ->
        run = easy_target(run)
        run = put_in(run.heroes[1].hero.speed, 0)
        run = TeamTraining.battle(run, hd(run.targets[1]).id)
        run = TeamTraining.battle_action(scope, run, %{auto: true})
        encounter = TeamTraining.active_encounter(run)
        [turn] = encounter.duel.battle.turns
        battle = %{encounter.duel.battle | turns: [put_in(turn.defender.silenced, true)]}
        duel = %{encounter.duel | battle: battle}
        %{run | resolution: %{duel: duel}, encounters: [%{encounter | duel: duel, battles: [battle]}]}
      end)

    encounter = record |> TeamRuns.state() |> TeamTraining.active_encounter()
    {:ok, view, html} = live(conn, TrainingEncounters.path(encounter, 1))
    assert has_element?(view, "#attack-button[disabled]")
    assert has_element?(view, "#training-auto-battle[aria-pressed=false]")

    [data] = html |> LazyHTML.from_fragment() |> LazyHTML.query("#combat-stage") |> LazyHTML.attribute("data-scene")
    assert %{"enabled" => true, "frame" => frame} = Jason.decode!(data)["trainingPlayback"]
    view |> element("#combat-stage") |> render_hook("training-playback-ready", %{"frame" => frame})

    saved = TeamRuns.get_encounter(scope, record.id, encounter.id)
    {:ok, replay} = TrainingEncounters.replay(saved)
    [_, attack] = hd(replay.battles).turns
    assert attack.attacker.hero_id == 1
    assert attack.attacker.silenced
    assert attack.skill_code == "basic_attack"
    assert is_nil(attack.item_code)
  end

  test "a pending battle can be resumed after reloading and foreign admins cannot access it", %{
    conn: conn,
    scope: scope,
    player: player
  } do
    record = team_run(scope, player)
    {:ok, pending} = TeamRuns.update(scope, record, fn run -> TeamTraining.battle(run, hd(run.targets[1]).id) end)
    [e] = TeamRuns.encounters(scope, record.id)
    {:ok, view, _} = live(conn, "/training")
    assert has_element?(view, "#team-resume[href='#{TrainingEncounters.path(e, 1)}']")
    refute has_element?(view, "#team-targets")
    assert TeamRuns.state(pending).phase == :engagement
    {other_scope, other_player} = team_account()
    other = build_conn() |> log_in_user(other_scope.user) |> put_session(:player_id, other_player.id)
    assert_raise Ecto.NoResultsError, fn -> live(other, "/training?run=#{record.id}") end
    assert_raise Ecto.NoResultsError, fn -> live(other, TrainingEncounters.path(e, 1)) end
  end

  test "later league battles keep the player's controls when a surviving opponent initiates", %{
    conn: conn,
    scope: scope,
    player: player
  } do
    record = team_run(scope, player)

    {:ok, record} =
      TeamRuns.update(scope, record, fn run ->
        run = %{run | turns_left: 0} |> TeamTraining.league() |> simple_league()
        e = TeamTraining.active_encounter(run)

        units =
          Map.new(e.units, fn {id, h} ->
            unit =
              cond do
                id in [1, 2] -> simple_unit(h, 1, 1)
                id >= 1000 -> simple_unit(h, 5000, 20)
                true -> %{h | hp: 5000, hero: %{run.heroes[id].hero | total_hp: 5000, item_hp: 0}}
              end

            {id, unit}
          end)

        duel = Moba.Game.Training.Combat.new_duel(units[1], units[hd(e.remaining.dire)])

        e = %{
          e
          | units: units,
            radiant: Enum.map(e.radiant, &units[&1.id]),
            dire: Enum.map(e.dire, &units[&1.id]),
            duel: duel,
            battles: [duel.battle]
        }

        run = %{run | encounters: [e], resolution: %{duel: duel}}

        Enum.reduce_while(1..10, run, fn _, current ->
          if length(TeamTraining.active_encounter(current).battles) == 3,
            do: {:halt, current},
            else: {:cont, TeamTraining.battle_action(scope, current, %{auto: true})}
        end)
      end)

    e = TeamTraining.active_encounter(TeamRuns.state(record))
    full = List.last(e.battles)
    assert length(e.battles) == 3
    assert full.attacker.player.id == -2
    assert full.defender.id == 3
    assert length(full.defender.skills) == 4
    path = TrainingEncounters.path(e, 3)
    {:ok, view, _} = live(conn, path)
    assert has_element?(view, "#attack-button[data-hero='3'][disabled]")

    scene =
      view
      |> element("#combat-stage")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#combat-stage")
      |> LazyHTML.attribute("data-scene")
      |> hd()
      |> Jason.decode!()

    view
    |> element("#combat-stage")
    |> render_hook("training-playback-ready", %{"frame" => scene["trainingPlayback"]["frame"]})

    assert has_element?(view, "#attack-button[data-hero='3']:not([disabled])")

    for skill <- full.defender.skills do
      assert has_element?(
               view,
               "#battle-bar .battle-skills-row img[src='#{MobaWeb.V2.Components.GameHelpers.image_url(skill)}']"
             )
    end

    {:ok, resumed, _} = live(conn, path)
    assert has_element?(resumed, "#attack-button[data-hero='3']:not([disabled])")

    resumed
    |> element("#combat-stage")
    |> render_hook("next-turn", %{"hero_id" => "3", "skill_id" => "", "item_id" => ""})

    saved = TeamTraining.active_encounter(TeamRuns.state(TeamRuns.get!(scope, record.id)))
    assert length(List.last(saved.battles).turns) == 2
    assert List.last(List.last(saved.battles).turns).attacker.hero_id == 3
  end

  test "a fallen hero must afford buyback, can sell items, and returns to targets after paying", %{
    conn: conn,
    scope: scope,
    player: player
  } do
    record = team_run(scope, player)

    {:ok, record} =
      TeamRuns.update(scope, record, fn run ->
        h = run.heroes[1]
        inventory = Enum.map(h.inventory, &Map.put(&1, :sale, 1080))

        put_in(run.heroes[1], %{
          h
          | hp: 0,
            energy: 0,
            inventory: inventory,
            hero: %{h.hero | pve_state: "dead", gold: 0}
        })
      end)

    before = TeamRuns.state(record)
    price = Game.buyback_price(before.heroes[1].hero)
    item = hd(before.heroes[1].inventory).item
    {:ok, view, _} = live(conn, "/training")
    assert has_element?(view, "#team-death-panel", "has fallen")
    assert has_element?(view, "#training-perfect-run", "Perfect")
    assert has_element?(view, "#team-buyback-farm-impact", "Avg Farm")
    assert has_element?(view, "#team-select-1[data-dead=true]", "Dead · Buyback")
    assert has_element?(view, "#buyback-hero[disabled]")
    assert has_element?(view, "#team-buyback-help", "Shop")
    assert has_element?(view, "#restart-team[data-confirm]", "Restart Team")
    assert has_element?(view, "#team-death-new-team[href='/new']", "New Team")
    refute has_element?(view, "#shard-buyback-hero")
    refute has_element?(view, "#team-targets")
    render_click(view, "buyback")
    render_click(view, "battle", %{"id" => hd(before.targets[1]).id})
    assert TeamRuns.state(TeamRuns.get!(scope, record.id)).phase == :playing
    assert TeamTraining.dead?(TeamRuns.state(TeamRuns.get!(scope, record.id)).heroes[1])
    assert has_element?(view, "#team-2-team-targets[data-hero='2']")
    refute has_element?(view, "#team-hero-panel-2 .death-panel")
    view |> element("#toggle-shop") |> render_click()
    assert has_element?(view, "#shop-modal.d-block")
    view |> element("#shop-modal [phx-click=select-inventory][data-item-code='#{item.code}']") |> render_click()
    sell_button = "#sell-#{item.id}"
    assert has_element?(view, sell_button, "Sell for #{Game.item_price(item)}")
    view |> element(sell_button) |> render_click()
    assert has_element?(view, "#training-perfect-run", "Perfect")
    assert has_element?(view, "#buyback-hero:not([disabled])")
    view |> element("#close-button") |> render_click()
    view |> element("#buyback-hero") |> render_click()
    refute has_element?(view, "#team-death-panel")
    refute has_element?(view, "#training-perfect-run")
    assert has_element?(view, "#team-targets[data-hero='1']")
    assert has_element?(view, "#team-select-1[data-dead=false]")
    saved = TeamRuns.state(TeamRuns.get!(scope, record.id))
    assert saved.heroes[1].hero.gold == Game.item_price(item) - price
    assert saved.heroes[1].hero.buybacks == 1
    assert saved.heroes[1].hero.total_gold_farm == before.heroes[1].hero.total_gold_farm - price
    assert saved.targets == before.targets
    assert saved.heroes[2] == before.heroes[2]
    {:ok, reloaded, _} = live(conn, "/training?run=#{record.id}")
    refute has_element?(reloaded, "#team-death-panel")
  end

  test "eligible team heroes buy back with Shards once without changing their farm or teammates", %{
    conn: conn,
    scope: scope,
    player: player
  } do
    player = player |> Ecto.Changeset.change(pve_tier: 4) |> Moba.Repo.update!() |> then(&Game.get_player!(&1.id))
    Moba.Accounts.update_user!(scope.user, %{shard_count: 100})
    record = team_run(scope, player)

    {:ok, record} =
      TeamRuns.update(scope, record, fn run ->
        h = run.heroes[1]
        put_in(run.heroes[1], %{h | hp: 0, energy: 0, deaths: 1, hero: %{h.hero | pve_state: "dead", gold: 0}})
      end)

    before = TeamRuns.state(record)
    {:ok, view, _} = live(conn, "/training")
    assert has_element?(view, "#shard-buyback-hero", "Use Shards")
    view |> element("#shard-buyback-hero") |> render_click()
    refute has_element?(view, "#team-death-panel")
    assert has_element?(view, "#team-targets[data-hero='1']")
    saved = TeamRuns.state(TeamRuns.get!(scope, record.id))
    assert saved.heroes[1].hp > 0
    assert saved.heroes[1].deaths == 1
    assert saved.heroes[1].hero.gold == 0
    assert saved.heroes[1].hero.total_gold_farm == before.heroes[1].hero.total_gold_farm
    assert saved.heroes[2] == before.heroes[2]
    balance = 100 - Moba.shard_buyback_price(100)
    assert Moba.Accounts.get_user!(scope.user.id).shard_count == balance
    render_click(view, "shard-buyback")
    assert Moba.Accounts.get_user!(scope.user.id).shard_count == balance
    assert {:error, :stale} = TeamRuns.shard_buyback(scope, record)
    assert Moba.Accounts.get_user!(scope.user.id).shard_count == balance
  end

  test "restarting a fallen team starts all three builds fresh and preserves the old run", %{
    conn: conn,
    scope: scope,
    player: player
  } do
    record = team_run(scope, player)

    {:ok, record} =
      TeamRuns.update(scope, record, fn run ->
        run = run |> easy_target() |> TeamTraining.battle(hd(run.targets[1]).id) |> finish_team(scope)
        h = run.heroes[1]
        put_in(run.heroes[1], %{h | hp: 0, hero: %{h.hero | pve_state: "dead"}})
      end)

    before = TeamRuns.state(record)
    {:ok, view, _} = live(conn, "/training")
    view |> element("#restart-team") |> render_click()
    fresh = TeamRuns.active(scope, player.id)
    assert fresh.id != record.id
    assert_redirect(view, "/training?run=#{fresh.id}")
    run = TeamRuns.state(fresh)
    assert run.phase == :playing
    assert run.league_tier == 0
    assert run.turns_left == 5
    assert run.encounters == []
    assert TeamRuns.encounters(scope, fresh.id) == []

    for id <- run.order do
      assert run.heroes[id].hero.level == 1
      assert run.heroes[id].hero.total_gold_farm == 0
      assert run.heroes[id].hero.name == before.heroes[id].hero.name
      assert run.heroes[id].hero.avatar.id == before.heroes[id].hero.avatar.id
      assert run.heroes[id].hp > 0
    end

    old = TeamRuns.state(TeamRuns.get!(scope, record.id))
    assert old.phase == :abandoned
    assert old.encounters == before.encounters
    assert {:error, :stale} = TeamRuns.restart(scope, record)
    assert {:error, {:live_redirect, %{to: path}}} = live(conn, "/training?run=#{record.id}")
    assert path == "/training?run=#{fresh.id}"
  end

  test "Master teams see Roshan's challenge and can start the final 3v1", %{conn: conn, scope: scope, player: player} do
    record = team_run(scope, player)
    {:ok, record} = TeamRuns.update(scope, record, &ready_for_roshan/1)
    boss = TeamTraining.boss_preview(TeamRuns.state(record))
    assert boss.hp == 10_000
    {:ok, view, _} = live(conn, "/training")
    assert has_element?(view, "#training-ascent-status", "Roshan awaits")
    assert has_element?(view, "#roshan-challenge[data-attempt='1']")
    assert has_element?(view, "#roshan-title", "Roshan")
    assert has_element?(view, "#roshan-health[aria-valuenow='#{boss.hp}'][aria-valuemax='#{boss.hp}']")
    assert has_element?(view, "#roshan-challenge .roshan-abilities img")
    assert has_element?(view, "#roshan-challenge .roshan-abilities img[alt='Strength of the Immortal']")
    assert has_element?(view, "#start-league-challenge.ascent-challenge:not([disabled])", "Fight Roshan")
    refute has_element?(view, "#roshan-recovery")
    refute has_element?(view, "#team-targets, #training-ascent .ascent-challenge")

    ids = view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query("[id]") |> LazyHTML.attribute("id")
    assert ids == Enum.uniq(ids)
    assert TeamRuns.get!(scope, record.id).lock_version == record.lock_version

    view |> element("#team-3-start-league-challenge") |> render_click()
    [encounter] = TeamRuns.encounters(scope, record.id)
    assert_redirect(view, TrainingEncounters.path(encounter, 1))
    pending = record.id |> then(&TeamRuns.get!(scope, &1)) |> TeamRuns.state() |> TeamTraining.active_encounter()
    assert pending.kind == :boss
    assert length(pending.radiant) == 3
    assert [roshan] = pending.dire
    assert roshan.hero.name == "Roshan"
    assert roshan.hp == boss.hp
  end

  test "Roshan retries show retained health and wait for pending teammate skill points", %{
    conn: conn,
    scope: scope,
    player: player
  } do
    record = team_run(scope, player)

    {:ok, record} =
      TeamRuns.update(scope, record, fn run ->
        run = ready_for_roshan(run)
        boss = TeamTraining.boss_preview(run)
        run = %{run | boss: %{boss | hp: div(boss.hp, 2)}, boss_attempts: 1}
        put_in(run.heroes[2].hero.skill_levels_available, 1)
      end)

    run = TeamRuns.state(record)
    {:ok, view, _} = live(conn, "/training")
    assert has_element?(view, "#roshan-challenge[data-attempt='2']")
    assert has_element?(view, "#roshan-health[aria-valuenow='5000'][aria-valuemax='10000']")
    assert has_element?(view, "#roshan-recovery", "Regenerated 5000 HP")
    assert has_element?(view, "#roshan-recovery", "final attempt")
    assert has_element?(view, "#start-league-challenge[disabled][aria-describedby=league-skill-warning]")
    assert has_element?(view, "#roshan-challenge button#league-skill-warning[aria-keyshortcuts=Space]")
    render_click(view, "league", %{"hero_id" => "1"})
    assert TeamRuns.state(TeamRuns.get!(scope, record.id)).phase == :playing

    current = TeamRuns.get!(scope, record.id)
    {:ok, record} = TeamRuns.update(scope, current, &put_in(&1.heroes[2].hero.skill_levels_available, 0))
    {:ok, retry, _} = live(conn, "/training")
    retry |> element("#start-league-challenge") |> render_click()
    pending = TeamRuns.get!(scope, record.id) |> TeamRuns.state() |> TeamTraining.active_encounter()
    assert hd(pending.dire).hp == run.boss.hp
  end

  defp ready_for_roshan(run) do
    heroes =
      Map.new(run.heroes, fn {id, h} ->
        {id, %{h | hero: %{h.hero | league_tier: Moba.master_league_tier(), pve_current_turns: 0}}}
      end)

    %{run | heroes: heroes, league_tier: Moba.master_league_tier(), goal: Moba.max_league_tier(), turns_left: 0}
  end

  test "a full roster challenge waits for every fallen hero's buyback", %{conn: conn, scope: scope, player: player} do
    record = team_run(scope, player)

    {:ok, record} =
      TeamRuns.update(scope, record, fn run ->
        heroes = Map.new(run.heroes, fn {id, h} -> {id, %{h | hero: %{h.hero | pve_current_turns: 0}}} end)
        run = %{run | selected: 2, turns_left: 0, heroes: heroes}
        h = run.heroes[1]
        put_in(run.heroes[1], %{h | hp: 0, energy: 0, hero: %{h.hero | pve_state: "dead"}})
      end)

    {:ok, view, _} = live(conn, "/training")
    assert has_element?(view, "#team-league-buyback")
    refute has_element?(view, "#start-league-challenge")
    render_click(view, "league")
    assert TeamRuns.encounters(scope, record.id) == []
    assert has_element?(view, "#team-2-team-buyback-select-1")
    assert has_element?(view, "#team-death-panel")
    view |> element("#buyback-hero") |> render_click()
    refute has_element?(view, "#team-league-buyback")
    assert has_element?(view, "#start-league-challenge")
    view |> element("#start-league-challenge") |> render_click()
    [e] = TeamRuns.encounters(scope, record.id)
    assert_redirect(view, TrainingEncounters.path(e, 1))
    run = TeamRuns.state(TeamRuns.get!(scope, record.id))
    assert length(TeamTraining.active_encounter(run).radiant) == 3
  end

  test "winning a league returns fallen heroes directly to their next targets", %{
    conn: conn,
    scope: scope,
    player: player
  } do
    record = team_run(scope, player)

    {:ok, record} =
      TeamRuns.update(scope, record, fn run ->
        %{run | turns_left: 0} |> TeamTraining.league() |> league_with_casualty() |> finish_team(scope)
      end)

    run = TeamRuns.state(record)
    e = hd(run.encounters)
    [first_enemy, second_enemy | _] = e.dire
    {:ok, first_battle, _} = live(conn, TrainingEncounters.path(e, 1))
    assert has_element?(first_battle, ".team-opponent-steps li[aria-disabled=false]")
    assert has_element?(first_battle, "#team-opponent-step-#{first_enemy.id}[data-state=next][aria-disabled=false]")
    assert has_element?(first_battle, "#team-opponent-step-#{second_enemy.id}[data-state=pending]")

    assert has_element?(
             first_battle,
             "#team-opponent-step-#{first_enemy.id} img[alt='#{first_enemy.hero.avatar.name}']"
           )

    refute has_element?(first_battle, "#training-battle-step-1")

    {:ok, second_battle, _} = live(conn, TrainingEncounters.path(e, 2))
    assert has_element?(second_battle, "#team-opponent-step-#{first_enemy.id}[data-state=defeated][aria-disabled=true]")
    assert has_element?(second_battle, "#team-opponent-step-#{second_enemy.id}[data-state=next][aria-disabled=false]")
    {:ok, last_battle, _} = live(conn, TrainingEncounters.path(e, length(e.battles)))
    assert has_element?(last_battle, "#training-battle-result .league-stage-cleared", "cleared · You Win")

    assert Enum.count(
             last_battle
             |> render()
             |> LazyHTML.from_fragment()
             |> LazyHTML.query(".team-opponent-steps [aria-disabled=true]")
           ) == 3

    assert run.heroes[1].deaths == 1
    assert run.heroes[1].hero.buybacks == 0
    {:ok, view, _} = live(conn, "/training?run=#{record.id}")
    refute has_element?(view, "#team-last-result")
    assert has_element?(view, "#team-select-1[data-dead=false]")
    assert has_element?(view, "#team-targets[data-hero='1']")
    refute has_element?(view, "#team-death-panel, #buyback-hero, #team-league-buyback")
    view |> element("#gank-#{hd(run.targets[1]).id}") |> render_click()
    [_, encounter] = TeamRuns.encounters(scope, record.id)
    assert_redirect(view, TrainingEncounters.path(encounter, 1))
  end

  test "completed teams and their collected heroes show team standings instead of solo rankings", %{
    conn: conn,
    scope: scope,
    player: player
  } do
    record = team_run(scope, player)
    {:ok, record} = TeamRuns.update(scope, record, &%{&1 | phase: :finished, league_tier: 4})
    assert {:error, {:live_redirect, %{to: path}}} = live(conn, "/training?run=#{record.id}")
    assert path == "/teams/#{record.id}"
    {:ok, result, _} = live(conn, path)
    assert has_element?(result, "#training-completion[data-outcome='qualified']", "Your team is ready for the Arena.")
    assert has_element?(result, "#completion-continue[href='/base']", "Return to Base")
    assert has_element?(result, "#training-team-ranking #team-ranking-#{record.id}[data-current=true]")
    assert has_element?(result, "#team-profile-view-hero-#{hd(record.hero_ids)}[href='/hero/#{hd(record.hero_ids)}']")
    assert has_element?(result, "#team-league-title", "Diamond")
    assert has_element?(result, "#team-ranking-scroll .hero-ranking-table")
    refute has_element?(result, ".team-profile-heading, #team-start-training, #team-training-complete, #hero-bar")
    refute has_element?(result, "#team-profile-performance", "Complete")
    refute has_element?(result, "#hero-review", "Team 3v3")
    assert has_element?(result, "#team-ranking-title", "Global rankings")
    assert has_element?(result, "#team-ranking-#{record.id} .hero-ranking-farm img[src='/images/league/4.png']")
    assert has_element?(result, "#team-ranking-#{record.id}[phx-hook=HalfScroll]")

    for {id, index} <- Enum.with_index(record.hero_ids) do
      hero = Game.get_hero!(id)
      assert has_element?(result, "#team-profile-tab-#{id}[aria-selected=#{index == 0}]", hero.avatar.name)
      assert has_element?(result, "#team-profile-hero-#{id} .hero-detail-stats")
      assert has_element?(result, "#team-profile-hero-#{id} .hero-detail-loadout img")

      assert has_element?(
               result,
               "#team-profile-view-hero-#{id} + #team-profile-player-#{id}[href='/player/#{player.id}']"
             )

      assert has_element?(result, "#team-profile-hero-#{id}#{if index > 0, do: ".d-none"}")
    end

    ids = result |> render() |> LazyHTML.from_fragment() |> LazyHTML.query("[id]") |> LazyHTML.attribute("id")
    assert ids == Enum.uniq(ids)
    profile = TeamRuns.profile!(scope, record.id)
    assert Enum.map(profile.heroes, & &1.id) == record.hero_ids
    assert profile.state == nil

    {:ok, hero, _} = live(conn, "/hero/#{hd(record.hero_ids)}")
    assert has_element?(hero, "#training-team-ranking #team-ranking-#{record.id}[data-current=true]")
    assert has_element?(hero, "#team-ranking-title", "Global rankings")
    assert has_element?(hero, "#team-ranking-scroll .hero-ranking-table")
    assert has_element?(hero, "#team-ranking-#{record.id} .hero-ranking-farm img[src='/images/league/4.png']")

    for profile <- [result, hero], id <- record.hero_ids do
      avatar_name = Game.get_hero!(id).avatar.name
      assert has_element?(profile, "#team-ranking-#{record.id} .hero-ranking-identity small", avatar_name)
    end

    refute has_element?(result, "#team-ranking-#{record.id} .hero-ranking-identity small", "Diamond League")
    refute has_element?(hero, "#hero-training-status")
    refute has_element?(hero, "#hero-ranking-switcher, #hero-leaderboard")
  end

  test "team profiles show average farm and share average team rankings with individual heroes", %{
    conn: conn,
    scope: scope,
    player: player
  } do
    record = team_run(scope, player)

    {:ok, record} =
      TeamRuns.update(scope, record, fn run ->
        heroes =
          Enum.reduce([{1, 12_000, 16_000}, {2, 18_000, 20_000}, {3, 21_001, 23_000}], run.heroes, fn {id, gold, xp},
                                                                                                      heroes ->
            Map.update!(heroes, id, &Game.Training.Loadouts.grant_farm(%{&1 | auto_buy: false}, gold, xp, run.catalog))
          end)

        %{run | heroes: heroes, phase: :finished}
      end)

    {:ok, team, _} = live(conn, "/teams/#{record.id}")
    assert has_element?(team, "#team-profile-performance dt", "Total avg farm")
    assert has_element?(team, "#team-profile-performance dt", "Avg XP farm")
    assert has_element?(team, "#team-profile-performance dt", "Avg Gold farm")
    assert has_element?(team, "#team-profile-performance .hero-farm-total[title='36667.0']", "36K")
    assert has_element?(team, "#team-profile-performance .hero-farm-xp[title='19666.67']", "19K")
    assert has_element?(team, "#team-profile-performance .hero-farm-gold[title='17000.33']", "17K")
    assert has_element?(team, "#training-team-ranking th", "Avg Farm")
    assert has_element?(team, "#team-ranking-#{record.id} .hero-ranking-farm[title='36667.0'] strong", "36K")

    {:ok, hero, _} = live(conn, "/hero/#{hd(record.hero_ids)}")
    assert has_element?(hero, "#training-team-ranking th", "Avg Farm")
    assert has_element?(hero, "#team-ranking-#{record.id} .hero-ranking-farm[title='36667.0'] strong", "36K")
    assert has_element?(hero, "#hero-detail-performance .hero-farm-total[title='28000']", "28K")
  end

  test "Perfect indicators on team and hero profiles use the completed team's average", %{
    conn: conn,
    scope: scope,
    player: player
  } do
    for {xp, perfect?} <- [{[37_700, 30_000, 22_300], true}, {[37_700, 30_000, 22_299], false}] do
      record = team_run(scope, player)

      {:ok, record} =
        TeamRuns.update(scope, record, fn run ->
          heroes =
            Map.new(Enum.zip(run.order, xp), fn {id, xp} ->
              h = run.heroes[id]
              {id, %{h | hero: %{h.hero | total_xp_farm: xp, total_gold_farm: 30_000}}}
            end)

          %{run | heroes: heroes, phase: :finished, league_tier: 6}
        end)

      {:ok, team, _} = live(conn, "/teams/#{record.id}")
      assert has_element?(team, "#team-perfect-run[data-toggle=tooltip]", "Perfect") == perfect?

      for id <- record.hero_ids do
        {:ok, hero, _} = live(conn, "/hero/#{id}")
        assert has_element?(hero, "#hero-perfect-run[data-toggle=tooltip]", "Perfect") == perfect?
      end
    end
  end

  test "completed team profiles are visible to other players but unfinished teams stay private", %{
    conn: conn,
    scope: scope,
    player: player
  } do
    {other_scope, other_player} = team_account()
    record = team_run(other_scope, other_player)
    assert_raise Ecto.NoResultsError, fn -> TeamRuns.profile!(scope, record.id) end
    {:ok, draft} = TeamRuns.draft(other_scope, other_player)
    assert_raise Ecto.NoResultsError, fn -> TeamRuns.profile!(scope, draft.id) end
    {:ok, record} = TeamRuns.update(other_scope, record, &%{&1 | phase: :finished})
    {:ok, view, _} = live(conn, "/teams/#{record.id}")
    assert has_element?(view, "#team-ranking-#{record.id} .hero-ranking-identity strong", record.name)
    assert has_element?(view, "#team-profile-player-#{hd(record.hero_ids)}[href='/player/#{other_player.id}']")
    refute has_element?(view, "#team-start-training, [id^=team-save-account], #customize-hero")
    assert TeamRuns.profile!(scope, record.id).player_id != player.id
  end

  test "guest team completion guides its owner from the rankings through registration to training", %{conn: conn} do
    guest = TeamRuns.start_guest!("profile-guest-#{System.unique_integer([:positive])}", hd(team_picks(%{user: nil})))
    scope = TeamRuns.scope(guest)
    {:ok, draft} = TeamRuns.draft(scope, guest)

    record =
      Enum.reduce(tl(team_picks(scope)), draft, fn pick, current ->
        {:ok, next} = TeamRuns.update(scope, current, &TeamTraining.add_pick(scope, &1, pick))
        next
      end)

    {:ok, record} =
      TeamRuns.update(scope, record, &%{TeamTraining.begin_run(&1) | phase: :finished, league_tier: 3})

    guest_conn = build_conn() |> init_test_session(player_id: guest.id)
    {:ok, owner, _} = live(guest_conn, "/teams/#{record.id}")
    assert has_element?(owner, "#training-completion[data-outcome='rank-up']")
    assert has_element?(owner, "#training-completion-title", "Novice")
    assert has_element?(owner, ".hero-detail-rankings > #training-completion + #training-team-ranking")

    assert has_element?(
             owner,
             "#completion-continue[href='/base'] #team-completion-arrow-#{record.id}.first-battle-arrow"
           )

    refute has_element?(owner, "#completion-shards, #completion-view-rewards, #pve-tier-rewards")

    assert has_element?(
             owner,
             "#team-profile-hero-#{hd(record.hero_ids)} .hero-detail-actions [id^=team-save-account][href='/users/register']"
           )

    {:ok, visitor, _} = live(conn, "/teams/#{record.id}")
    refute has_element?(visitor, "[id^=team-save-account], #team-start-training")
    refute has_element?(visitor, "#training-completion")

    assert {:ok, base, _} =
             owner
             |> element("#completion-continue", "Return to Base")
             |> render_click()
             |> follow_redirect(guest_conn, "/base")

    registration_path = "/users/register?from=training"
    assert has_element?(base, "#base-invoke-btn[href='#{registration_path}']", "Register to continue training")
    assert has_element?(base, "#base-invoke-btn .first-battle-arrow")

    {:ok, registration, _} = live(guest_conn, registration_path)
    form = form(registration, "#registration_form", user: valid_user_attributes())
    render_submit(form)
    registered_conn = follow_trigger_action(form, guest_conn)
    assert redirected_to(registered_conn) == "/base"

    {:ok, registered_base, _} = registered_conn |> recycle() |> live("/base")
    assert has_element?(registered_base, "#base-invoke-btn[href='/new']", "Start training")
    assert has_element?(registered_base, "#base-invoke-btn .first-battle-arrow")

    assert {:ok, _, _} =
             registered_base
             |> element("#base-invoke-btn")
             |> render_click()
             |> follow_redirect(registered_conn, "/new")

    {:ok, later_base, _} = build_conn() |> log_in_player(player_id: guest.id) |> live("/base")
    refute has_element?(later_base, "#base-invoke-btn .first-battle-arrow")
  end

  test "an existing draft passes its saved builds to the browser", %{conn: conn, scope: scope, player: player} do
    [first, second | _] = team_picks(scope)
    first_avatar = Game.get_avatar!(first["avatar"])
    {first_skills, _} = Game.skill_build_for(first_avatar.role, 0)
    first = Map.merge(first, %{"skills" => Enum.map(first_skills, &to_string(&1.id)), "preset" => 0})
    {:ok, draft} = TeamRuns.draft(scope, player)
    {:ok, draft} = TeamRuns.update(scope, draft, &TeamTraining.add_pick(scope, &1, first))
    {:ok, _draft} = TeamRuns.update(scope, draft, &TeamTraining.add_pick(scope, &1, Map.put(second, "preset", nil)))

    {:ok, view, _} = live(conn, "/new")

    [json] =
      view
      |> element("#invoke-modern")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-creation]")
      |> LazyHTML.attribute("data-creation")

    assert [%{"avatar" => first_id, "preset" => 0}, %{"avatar" => second_id, "preset" => nil}] =
             Jason.decode!(json)["draft_picks"]

    assert first_id == to_string(first["avatar"])
    assert second_id == to_string(second["avatar"])
  end
end
