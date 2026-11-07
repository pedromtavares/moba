defmodule MobaWeb.V2.OnboardingSkillSelectionTest do
  use MobaWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Moba.Repo
  alias Moba.Game.{TeamRuns, TeamTraining, TrainingEncounters}

  test "new solo heroes preselect their ultimate for guests and registered players", %{conn: conn} do
    for player <- [Game.create_player!(%{}), create_player!()] do
      avatar = Game.get_avatar_by_code!("juggernaut") |> Repo.preload(:ultimate)
      {skills, _} = Game.skill_build_for("carry", 0)
      hero = Game.create_current_pve_hero!(%{name: "New hero"}, player, avatar, skills) |> then(&Game.get_hero!(&1.id))

      enemy =
        Game.Heroes.create!(%{name: "Target", total_hp: 5000}, nil, avatar, skills) |> then(&Game.get_hero!(&1.id))

      battle = Engine.create_pve_battle!(%{attacker: hero, defender: enemy, difficulty: "weak"})
      {:ok, view, _} = live(log_in_player(conn, player_id: player.id), "/battles/#{battle.id}")
      assert has_element?(view, "#attack-button[data-skill='#{avatar.ultimate.id}']:not([disabled])")
      assert has_element?(view, "#active-skill-name", "Omnislash")
      assert has_element?(view, "#active-skill-#{avatar.ultimate.id}[aria-pressed=true]")
    end
  end

  test "the newly created opening roster preselects and auto-casts its ultimate through the actual battle page", %{
    conn: conn
  } do
    player = create_player!() |> then(&Game.get_player!(&1.id))
    scope = %{user: player.user}
    {:ok, record} = TeamRuns.draft(scope, player)

    record =
      Enum.reduce(~w(juggernaut lina tusk), record, fn code, record ->
        avatar = Game.get_avatar_by_code!(code)
        {skills, _} = Game.skill_build_for(avatar.role, 0)
        pick = %{"avatar" => to_string(avatar.id), "skills" => Enum.map(skills, &to_string(&1.id))}
        {:ok, record} = TeamRuns.update(scope, record, &TeamTraining.add_pick(scope, &1, pick))
        record
      end)

    {:ok, record} = TeamRuns.update(scope, record, &TeamTraining.begin_run/1)

    {:ok, record} =
      TeamRuns.update(scope, record, fn run ->
        target = hd(run.targets[1])
        enemy = %{target.opponent | hero: %{target.opponent.hero | total_hp: 5000}, hp: 5000}
        run = put_in(run.targets[1], [%{target | opponent: enemy, defender: enemy.hero} | tl(run.targets[1])])
        TeamTraining.battle(run, target.id)
      end)

    run = TeamRuns.state(record)
    ultimate = Enum.find(run.heroes[1].hero.skills, & &1.ultimate)
    encounter = TeamTraining.active_encounter(run)
    {:ok, view, _} = live(log_in_player(conn, player_id: player.id), TrainingEncounters.path(encounter, 1))
    assert has_element?(view, "#attack-button[data-skill='#{ultimate.id}']:not([disabled])")
    assert has_element?(view, "#active-skill-name", "Omnislash")
    assert has_element?(view, "#active-skill-#{ultimate.id}[aria-pressed=true]")
    view |> element("#training-auto-battle") |> render_click()

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

    run = TeamRuns.state(TeamRuns.get!(scope, record.id))
    battle = TeamTraining.active_encounter(run).duel.battle
    assert hd(battle.turns).skill_code == "omnislash"
  end
end
