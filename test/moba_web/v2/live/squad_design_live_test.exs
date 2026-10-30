defmodule MobaWeb.V2.SquadDesignLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "team builder creates, fills, reorders and edits a defensive lineup", %{conn: conn} do
    player = create_player!()
    [first, second | _] = heroes(player, 3)
    {:ok, view, _} = live(init_test_session(conn, player_id: player.id), "/arena/edit")
    assert has_element?(view, "#teams-hud #team-name")
    view |> form("#arena-team-form", %{"team" => %{"name" => "Five stack"}}) |> render_submit()
    team = Game.list_teams(player) |> List.first()
    assert has_element?(view, "#team-row-#{team.id}[aria-pressed=true]")

    for hero <- [first, second] do
      view |> element("#add-button-#{hero.id}") |> render_click()
      assert has_element?(view, "#available-hero-#{hero.id} .roster-picked")
    end

    assert has_element?(view, "#team-hero-#{first.id} .roster-position", "1")
    assert has_element?(view, "#move-up-#{first.id}[disabled]")
    view |> element("#move-up-#{second.id}") |> render_click()
    assert has_element?(view, "#team-hero-#{second.id} .roster-position", "1")
    assert Game.list_teams(player) |> hd() |> Map.get(:pick_ids) == [second.id, first.id]
    render_click(view, "toggle-defensive", %{"value" => "on"})
    assert Game.list_teams(player) |> hd() |> Map.get(:defensive)
    assert has_element?(view, "#team-row-#{team.id}", "Defensive")
    view |> element("#edit-hero-#{first.id}") |> render_click()
    assert has_element?(view, "#teams-hud[data-editing-hero=true]")
    assert has_element?(view, "#hero-bar #edit-button")
    view |> element("#remove-hero-#{second.id}") |> render_click()
    refute has_element?(view, "#team-hero-#{second.id}")
    assert has_element?(view, "#team-empty-slot-2")
  end

  test "match picking keeps the numbered lineup and source selection in sync", %{conn: conn} do
    player = create_player!()
    picks = heroes(player, 5)
    opponent = create_player!()
    match = match(player, opponent, %{generated_picks: Enum.map(picks, & &1.id)})
    {:ok, view, _} = live(init_test_session(conn, player_id: player.id), "/matches/#{match.id}")
    view |> element("#available-heroes-button") |> render_click()

    for hero <- picks,
        do: view |> element("#generated-hero-#{hero.id} #pick-hero-#{hero.id}-available") |> render_click()

    assert has_element?(view, "#start-match-button")
    assert has_element?(view, "#match-pick-status-title", "Lineup ready")
    refute has_element?(view, "#match-empty-slot-1")
    [first, second | _] = picks
    view |> element("#move-down-#{first.id}") |> render_click()
    assert has_element?(view, "#hero-#{second.id} .roster-position", "1")
    assert has_element?(view, "#hero-#{first.id} .roster-position", "2")
    view |> element("#lineup-unpick-#{first.id}") |> render_click()
    refute has_element?(view, "#start-match-button")
    assert has_element?(view, "#match-empty-slot-5")
    refute has_element?(view, "#generated-hero-#{first.id} .roster-picked")
    # Picking and reordering remain local until the match is started.
    assert Game.get_match!(match.id).player_picks == []
  end

  test "completed match reviews keep player perspective and never expose reorder controls", %{conn: conn} do
    player = create_player!()
    opponent = create_player!()
    hero = Game.create_hero!(%{name: "Champion"}, player, strong_avatar(), base_skills())
    enemy = Game.create_hero!(%{name: "Challenger"}, opponent, weak_avatar(), base_skills())
    match = match(player, opponent, %{player_picks: [hero.id], opponent_picks: [enemy.id]})

    battle =
      Engine.create_match_battle!(%{
        attacker: enemy,
        attacker_player: opponent,
        defender: hero,
        defender_player: player,
        match: match
      })

    Game.Matches.update!(match, %{phase: "scored", winner_id: player.id})
    {:ok, view, _} = live(init_test_session(conn, player_id: player.id), "/matches/#{match.id}")
    assert has_element?(view, "#winner-card[data-complete=true]", "#{Game.get_player!(player.id).user.username} wins")
    assert has_element?(view, "#battle-summary-#{battle.id} .match-summary-hero[data-winner=true] img")
    assert has_element?(view, "#battle-summary-#{battle.id} [role=progressbar][aria-label='Champion health']")
    assert has_element?(view, "#battle-summary-#{battle.id} [role=progressbar][aria-label='Challenger health']")
    assert has_element?(view, "#battle-summary-#{battle.id} [role=progressbar][aria-label='Champion energy']")
    assert has_element?(view, "#battle-summary-#{battle.id} [role=progressbar][aria-label='Challenger energy']")
    refute has_element?(view, "#battle-summary-#{battle.id} .match-summary-hero > span")
    refute has_element?(view, "#battle-summary-#{battle.id} .resource-gauge[data-toggle=tooltip]")
    refute has_element?(view, "#battle-review-#{battle.id}")
    view |> element("#match-details-toggle[aria-pressed=false]") |> render_click()
    assert has_element?(view, "#match-details-toggle[aria-pressed=true]", "Summary")

    assert has_element?(
             view,
             "#battle-review-#{battle.id} .match-battle-unit:first-child .match-battle-hero",
             "Champion"
           )

    assert has_element?(view, "#battle-review-#{battle.id} .match-battle-unit:last-child[data-dead=true]", "Challenger")
    assert has_element?(view, "#battle-review-#{battle.id} [role=progressbar][aria-label='Champion health']")
    assert has_element?(view, "#battle-review-#{battle.id} [role=progressbar][aria-label='Champion energy']")
    refute has_element?(view, "[phx-click=move-up], [phx-click=move-down], #start-match-button")
    refute has_element?(view, "#picks-card")
    assert has_element?(view, "#opponent-hero-#{enemy.id} [data-defeated=true]", "Fallen")
    assert has_element?(view, "#hero-#{hero.id} [data-defeated=false]")

    view |> element("#match-details-toggle") |> render_click()
    assert has_element?(view, "#battle-summary-#{battle.id}")
    refute has_element?(view, "#battle-review-#{battle.id}")

    spectator = create_player!()
    {:ok, watching, _} = live(init_test_session(conn, player_id: spectator.id), "/matches/#{match.id}")
    assert has_element?(watching, "#match-battles #battle-summary-#{battle.id}")
    refute has_element?(watching, "[phx-click=pick-hero]")
  end

  defp heroes(player, count) do
    for index <- 1..count do
      Game.create_hero!(
        %{name: "Hero #{index}", finished_at: Timex.now(), league_tier: 5},
        player,
        base_avatar(),
        base_skills()
      )
    end
  end

  defp match(player, opponent, attrs) do
    Game.Matches.create!(
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
