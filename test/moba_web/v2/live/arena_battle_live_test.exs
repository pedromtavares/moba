defmodule MobaWeb.V2.ArenaBattleLiveTest do
  use MobaWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Moba.Game.Matches

  setup do
    player = create_player!(%{pve_tier: 1})
    opponent = create_player!(%{pve_tier: 1})
    own = strong_avatar()
    enemy = weak_avatar()

    picks =
      for n <- 1..3,
          do:
            Game.create_hero!(
              %{name: "Hero #{n}", pve_tier: 1, league_tier: 6, finished_at: Timex.now()},
              player,
              own,
              base_skills()
            )

    enemies = for n <- 1..3, do: Game.create_hero!(%{name: "Enemy #{n}"}, opponent, enemy, base_skills())

    match =
      Matches.create!(%{
        player_id: player.id,
        opponent_id: opponent.id,
        type: "manual",
        generated_picks: [],
        opponent_picks: Enum.map(enemies, & &1.id),
        player_picks: []
      })

    %{player: Game.get_player!(player.id), match: match, picks: picks}
  end

  test "selecting a lineup starts manual combat on the battle route", a do
    conn = log_in_player(a.conn, player_id: a.player.id)
    {:ok, view, _} = live(conn, "/matches/#{a.match.id}")
    for hero <- a.picks, do: render_click(view, "pick-hero", %{"id" => hero.id})
    view |> element("#start-match-button") |> render_click()
    assert_patch_or_redirect(view, a.match.id)
  end

  test "manual actions, pause buttons, next pairing and reload retain the cinematic layout", a do
    {:ok, match} = Game.start_match(a.match, a.player, Enum.map(a.picks, & &1.id), interactive: true)
    conn = log_in_player(a.conn, player_id: a.player.id)
    {:ok, view, _} = live(conn, "/matches/#{match.id}/battles")
    assert has_element?(view, "#arena-battle-page #combat-stage")
    assert has_element?(view, "#training-auto-battle[aria-keyshortcuts='T']", "Auto battle")
    assert has_element?(view, "#training-auto-match[aria-keyshortcuts='G']", "Auto all battles")
    assert has_element?(view, "#attack-button:not([disabled])")
    view |> element("#training-auto-battle") |> render_click()
    assert has_element?(view, "#training-auto-battle[aria-pressed=true]", "Pause")
    view |> element("#training-auto-battle") |> render_click()
    assert has_element?(view, "#training-auto-battle[aria-pressed=false]", "Auto battle")

    view
    |> with_target("#arena-match-#{match.id}")
    |> render_hook("next-turn", %{skill_id: "", item_id: "", hero_id: to_string(hd(a.picks).id)})

    assert has_element?(view, "#arena-fight-result")
    assert has_element?(view, "#arena-fight-result .league-outcome-heading #arena-result-title", "wins")
    refute has_element?(view, "#arena-fight-result.is-match-result")
    refute has_element?(view, "#arena-fight-result .arena-result-rating")
    assert has_element?(view, "#arena-next-battle[data-battle-continue=true]")
    assert has_element?(view, "#battle-bar + .battle-lineup-footer #arena-roster-summary")
    refute has_element?(view, "#battle-bar .arena-battle-chapters")
    assert has_element?(view, ".arena-summary-unit.is-fallen")
    view |> element("#arena-next-battle") |> render_click()
    assert length(Engine.list_match_battles(match.id)) == 2
    assert has_element?(view, "#attack-button:not([disabled])")
    details_path = "/matches/#{match.id}/battles"
    assert {:error, {:live_redirect, %{to: ^details_path}}} = live(conn, "/matches/#{match.id}")
    {:ok, resumed, _} = live(conn, details_path)
    assert has_element?(resumed, "#arena-battle-page #attack-button")
    assert has_element?(resumed, "#arena-roster-summary")
    assert LazyHTML.from_fragment(render(resumed)) |> LazyHTML.query(".arena-summary-unit") |> Enum.count() == 6
    refute has_element?(resumed, ".match-columns")
  end

  test "public spectators see the same battlefield without combat controls", a do
    {:ok, match} = Game.start_match(a.match, a.player, Enum.map(a.picks, & &1.id), interactive: true)
    spectator = create_player!()
    conn = log_in_player(a.conn, player_id: spectator.id)
    {:ok, view, _} = live(conn, "/matches/#{match.id}/battles")
    refute has_element?(view, "#training-auto-battle")
    assert has_element?(view, "#attack-button[disabled]")

    view
    |> with_target("#arena-match-#{match.id}")
    |> render_hook("next-turn", %{skill_id: "", item_id: "", hero_id: to_string(hd(a.picks).id)})

    assert Engine.latest_match_battle(match.id).turns == []
  end

  test "a stunned hero passes its Arena turn with auto battle off", a do
    {:ok, match} = Game.start_match(a.match, a.player, Enum.map(a.picks, & &1.id), interactive: true)
    battle = Engine.latest_match_battle(match.id)
    opening = Engine.build_turn(battle)

    Moba.Repo.insert!(%Moba.Engine.Schema.Turn{
      battle_id: battle.id,
      number: 1,
      skill_code: "basic_attack",
      attacker: opening.defender,
      defender: %{opening.attacker | stunned: true}
    })

    conn = log_in_player(a.conn, player_id: a.player.id)
    {:ok, view, html} = live(conn, "/matches/#{match.id}/battles")
    assert has_element?(view, "#attack-button[disabled]")
    assert has_element?(view, "#training-auto-battle[aria-pressed=false]")

    [data] = html |> LazyHTML.from_fragment() |> LazyHTML.query("#combat-stage") |> LazyHTML.attribute("data-scene")
    assert %{"enabled" => true, "frame" => frame} = Jason.decode!(data)["trainingPlayback"]
    view |> element("#combat-stage") |> render_hook("training-playback-ready", %{"frame" => frame})

    [previous, passed] = Engine.latest_match_battle(match.id).turns
    assert passed.attacker.player_id == a.player.id
    assert passed.attacker.stunned
    assert is_nil(passed.skill_code)
    assert passed.defender.current_hp == previous.attacker.current_hp
    assert has_element?(view, "#training-auto-battle[aria-pressed=false]")
  end

  test "the first batch fills the library and collection selections can be removed directly", a do
    for n <- 1..10,
        do:
          Game.create_hero!(
            %{name: "Extra #{n}", league_tier: 6, finished_at: Timex.now()},
            a.player,
            strong_avatar(),
            base_skills()
          )

    for n <- 1..7,
        do: Game.create_team!(%{player_id: a.player.id, name: "Team #{n}", pick_ids: Enum.map(a.picks, & &1.id)})

    {:ok, view, _} = live(log_in_player(a.conn, player_id: a.player.id), "/matches/#{a.match.id}")
    document = LazyHTML.from_fragment(render(view))
    assert document |> LazyHTML.query(".arena-draft-team-list .squad-team-choice") |> Enum.count() == 6
    assert document |> LazyHTML.query(".arena-collection-tile") |> Enum.count() == 12
    first_id = hd(a.picks).id
    view |> element("#pick-hero-#{first_id}-trained") |> render_click()
    assert has_element?(view, "#collection-unpick-#{first_id}")
    view |> element("#collection-unpick-#{first_id}") |> render_click()
    refute has_element?(view, "#collection-unpick-#{first_id}")
    assert has_element?(view, "#match-empty-slot-1")
    team = Game.list_teams(a.player) |> Enum.max_by(& &1.id)
    view |> element("#pick-team-#{team.id}") |> render_click()
    assert has_element?(view, "#clear-team-#{team.id}")
    assert has_element?(view, ".arena-draft-level[data-toggle=tooltip]", "Level")
    refute has_element?(view, ".arena-draft-stats")
    view |> element("#clear-team-#{team.id}") |> render_click()
    assert has_element?(view, "#match-empty-slot-1")
    assert length(Game.list_teams(a.player)) == 7
    view |> element("#arena-teams-next") |> render_click()
    assert LazyHTML.from_fragment(render(view)) |> LazyHTML.query(".squad-team-choice") |> Enum.count() == 1
    view |> element("#arena-heroes-next") |> render_click()
    assert LazyHTML.from_fragment(render(view)) |> LazyHTML.query(".arena-collection-tile") |> Enum.count() == 1
    assert has_element?(view, "#arena-heroes-next[disabled]")
  end

  test "auto all battles advances frames through the whole match and stops at its result", a do
    {:ok, match} = Game.start_match(a.match, a.player, Enum.map(a.picks, & &1.id), interactive: true)
    conn = log_in_player(a.conn, player_id: a.player.id)
    {:ok, view, _} = live(conn, "/matches/#{match.id}/battles")
    view |> element("#training-auto-match") |> render_click()

    Enum.reduce_while(1..100, nil, fn _, _ ->
      if Matches.get_match!(match.id).phase == "scored" do
        {:halt, nil}
      else
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

        {:cont, nil}
      end
    end)

    assert Matches.get_match!(match.id).phase == "scored"
    assert has_element?(view, "#arena-return-complete[href='/matches/#{match.id}']", "Match summary")
    refute has_element?(view, "#training-auto-match")
    assert has_element?(view, "#arena-fight-result", "Arena Rating")
    assert has_element?(view, "#arena-fight-result.is-match-result[data-result=victory] .arena-result-emblem .ui-icon")
    rewards = Matches.get_match!(match.id).rewards.attacker_pvp_points
    assert has_element?(view, "#arena-result-title.arena-result-rating strong", "+#{rewards}")

    assert has_element?(
             view,
             "#arena-fight-result .league-outcome-heading #arena-return-complete[aria-keyshortcuts=Space]"
           )

    assert {:ok, summary, _} = view |> element("#arena-return-complete") |> render_click() |> follow_redirect(conn)

    assert has_element?(summary, "#match-hud.arena-match-review #match-battles")
    assert has_element?(summary, "#arena-match-details[href='/matches/#{match.id}/battles']")
  end

  test "automatic results open the final cinematic battle and chapters have stable links", a do
    match = Matches.update!(a.match, %{type: "auto"})
    {:ok, match} = Game.start_match(match, a.player, Enum.map(a.picks, & &1.id))
    [first | _] = battles = Engine.list_match_battles(match.id)
    last = List.last(battles)
    assert first.id != last.id

    conn = log_in_player(a.conn, player_id: a.player.id)
    details = "/matches/#{match.id}/battles"
    first_path = "#{details}?battle=#{first.id}"
    {:ok, summary, _} = live(conn, "/matches/#{match.id}")
    assert has_element?(summary, "#match-hud.arena-match-review #match-battles")
    assert has_element?(summary, "#battle-summary-#{first.id}[href='#{first_path}']")

    {:ok, replay, _} = summary |> element("#arena-match-details") |> render_click() |> follow_redirect(conn)
    assert has_element?(replay, "#arena-inspect-#{last.id}[aria-current=step]")
    assert has_element?(replay, "#arena-fight-result.is-match-result")
    refute has_element?(replay, "#training-auto-battle, #attack-button:not([disabled])")

    replay |> element("#combat-log-toggle") |> render_click()

    assert has_element?(
             replay,
             "#hero-battle[role=dialog][aria-modal=true]:not([hidden]) #arena-combat-log-title",
             "Battle log"
           )

    assert has_element?(replay, "#hero-battle #turn-1")
    assert has_element?(replay, "#battle-bar[inert] #arena-fight-result")

    replay |> element("#arena-combat-log-close") |> render_click()
    assert has_element?(replay, "#hero-battle[hidden]")
    assert has_element?(replay, "#battle-bar:not([inert]) #arena-fight-result")

    replay |> element("#arena-inspect-#{first.id}") |> render_click()
    assert_patch(replay, first_path)
    assert has_element?(replay, "#arena-inspect-#{first.id}[aria-current=step]")
    assert has_element?(replay, "#arena-next-recorded-battle[href='#{details}?battle=#{Enum.at(battles, 1).id}']")
    refute has_element?(replay, "#arena-fight-result.is-match-result")
    assert {:error, {:live_redirect, %{to: ^first_path}}} = live(conn, "/battles/#{first.id}")

    {:ok, selected, _} = live(conn, first_path)
    assert has_element?(selected, "#arena-inspect-#{first.id}[aria-current=step]")
  end

  defp assert_patch_or_redirect(view, match_id) do
    # Await the task through LiveView's redirect assertion, without arbitrary sleeps.
    path = assert_redirect(view)
    battle = Engine.latest_match_battle(match_id)
    assert elem(path, 0) == "/matches/#{match_id}/battles"
    assert battle.turns == []
  end
end
