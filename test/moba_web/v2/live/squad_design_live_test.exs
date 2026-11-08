defmodule MobaWeb.V2.SquadDesignLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "team builder creates, fills, reorders and edits a defensive lineup", %{conn: conn} do
    player = create_player!()
    [first, second | _] = heroes(player, 3)
    {:ok, view, _} = live(log_in_player(conn, player_id: player.id), "/arena/edit")
    assert has_element?(view, "#teams-hud #team-name")
    assert has_element?(view, "#create-team-button .ui-plus")
    view |> form("#arena-team-form", %{"team" => %{"name" => "Three stack"}}) |> render_submit()
    team = Game.list_teams(player) |> List.first()
    assert has_element?(view, "#team-row-#{team.id}[aria-pressed=true]")

    lineup = element(view, "#team-workshop-layout")
    assert has_element?(view, "#add-button-#{first.id}[data-lineup-add]")
    assert has_element?(view, "#team-empty-slot-1[data-lineup-empty]")
    render_hook(lineup, "add-hero", %{"id" => "#{first.id}", "lineup_id" => team.id + 1})
    assert has_element?(view, "#team-empty-slot-1")
    render_hook(lineup, "add-hero", %{"id" => "#{first.id}", "lineup_id" => team.id})
    assert has_element?(view, "#available-hero-#{first.id} .roster-picked")
    assert has_element?(view, "#add-button-#{first.id}[disabled]:not([data-lineup-add])")
    view |> element("#add-button-#{second.id}") |> render_click()
    assert has_element?(view, "#available-hero-#{second.id} .roster-picked")

    assert has_element?(view, "#team-hero-#{first.id} .roster-position", "1")
    assert has_element?(view, "#team-hero-#{first.id} [data-lineup-grip]")
    render_hook(lineup, "reorder-lineup", %{"lineup_id" => team.id, "hero_ids" => [second.id, second.id]})
    assert Game.list_teams(player) |> hd() |> Map.get(:pick_ids) == [first.id, second.id]
    render_hook(lineup, "reorder-lineup", %{"lineup_id" => team.id, "hero_ids" => [second.id, first.id]})
    assert has_element?(view, "#team-hero-#{second.id} .roster-position", "1")
    assert Game.list_teams(player) |> hd() |> Map.get(:pick_ids) == [second.id, first.id]
    render_click(view, "toggle-defensive", %{"value" => "on"})
    assert Game.list_teams(player) |> hd() |> Map.get(:defensive)
    assert has_element?(view, "#team-row-#{team.id}", "Defensive")
    view |> element("#edit-hero-#{first.id}") |> render_click()
    assert has_element?(view, "#teams-hud[data-editing-hero=true]")
    assert has_element?(view, "#hero-bar #edit-button")
    view |> element("#close-team-customization") |> render_click()
    refute has_element?(view, "#hero-bar")
    assert has_element?(view, "#teams-hud[data-editing-hero=false]")
    view |> element("#remove-hero-#{second.id}") |> render_click()
    refute has_element?(view, "#team-hero-#{second.id}")
    assert has_element?(view, "#team-empty-slot-2")
  end

  test "team libraries page independently and collection removals update the saved lineup", %{conn: conn} do
    player = create_player!()
    picks = heroes(player, 25)

    for index <- 1..7 do
      Game.create_team!(%{name: "Stack #{index}", player_id: player.id, pick_ids: [hd(picks).id]})
    end

    {:ok, view, _} = live(log_in_player(conn, player_id: player.id), "/arena/edit")
    document = LazyHTML.from_fragment(render(view))
    assert document |> LazyHTML.query(".workshop-team-card") |> Enum.count() == 5
    assert document |> LazyHTML.query(".team-workshop-layout > #heroes-container") |> Enum.count() == 1
    assert document |> LazyHTML.query(".workshop-collection-hero") |> Enum.count() == 24
    assert has_element?(view, "#teams-page-previous[disabled]")
    assert has_element?(view, "#heroes-page-previous[disabled]")

    view |> element("#teams-page-next") |> render_click()
    assert LazyHTML.from_fragment(render(view)) |> LazyHTML.query(".workshop-team-card") |> Enum.count() == 2
    assert has_element?(view, "#teams-page-next[disabled]")
    view |> element("#heroes-page-next") |> render_click()
    assert LazyHTML.from_fragment(render(view)) |> LazyHTML.query(".workshop-collection-hero") |> Enum.count() == 1
    assert has_element?(view, "#heroes-page-next[disabled]")
    view |> element("#edit-hero-#{hd(picks).id}") |> render_click()
    assert LazyHTML.from_fragment(render(view)) |> LazyHTML.query(".workshop-collection-hero") |> Enum.count() == 6
    assert has_element?(view, "#heroes-page-previous[disabled]")
    assert LazyHTML.from_fragment(render(view)) |> LazyHTML.query(".workshop-team-card") |> Enum.count() == 3
    view |> element("#close-team-customization") |> render_click()
    assert LazyHTML.from_fragment(render(view)) |> LazyHTML.query(".workshop-collection-hero") |> Enum.count() == 24
    # Navigating a library never changes the selected team.
    assert has_element?(view, "#team-hero-#{hd(picks).id}")
    view |> element("#collection-remove-#{hd(picks).id}") |> render_click()
    refute has_element?(view, "#team-hero-#{hd(picks).id}")
    assert has_element?(view, "#team-empty-slot-1")

    view |> form("#arena-team-form", %{"team" => %{"name" => "New stack"}}) |> render_submit()
    team = Enum.find(Game.list_teams(player), &(&1.name == "New stack"))
    assert has_element?(view, "#team-row-#{team.id}[aria-pressed=true]")
    assert has_element?(view, "#current-team-title", "New stack")
  end

  test "match picking keeps the numbered lineup and source selection in sync", %{conn: conn} do
    player = create_player!()
    picks = heroes(player, 3)
    opponent = create_player!()
    match = match(player, opponent, %{generated_picks: Enum.map(picks, & &1.id)})
    {:ok, view, _} = live(log_in_player(conn, player_id: player.id), "/matches/#{match.id}")
    refute has_element?(view, "#available-heroes-button")

    [first, second, third] = picks
    lineup = element(view, "#match-hud")
    assert has_element?(view, "#pick-hero-#{first.id}-trained[data-lineup-add]")
    assert has_element?(view, "#match-empty-slot-1[data-lineup-empty]")
    render_hook(lineup, "pick-hero", %{"id" => "#{first.id}", "lineup_id" => match.id + 1})
    assert has_element?(view, "#match-empty-slot-1")
    render_hook(lineup, "pick-hero", %{"id" => "#{first.id}", "lineup_id" => match.id})
    assert has_element?(view, "#hero-#{first.id} .roster-actions > span", "1")
    assert has_element?(view, "#pick-hero-#{first.id}-trained[disabled]:not([data-lineup-add])")

    for hero <- [second, third],
        do: view |> element("#pick-hero-#{hero.id}-trained") |> render_click()

    assert has_element?(view, "#start-match-button")
    refute has_element?(view, "#match-empty-slot-1")
    render_hook(lineup, "reorder-lineup", %{"lineup_id" => match.id, "hero_ids" => [second.id, first.id, third.id]})

    assert has_element?(view, "#hero-#{second.id} .roster-actions > span", "1")
    assert has_element?(view, "#hero-#{first.id} .roster-actions > span", "2")
    view |> element("#lineup-unpick-#{first.id}") |> render_click()
    assert has_element?(view, "#start-match-button[disabled]")
    assert has_element?(view, "#match-empty-slot-3")
    refute has_element?(view, "#collection-unpick-#{first.id}")
    # Picking and reordering remain local until the match is started.
    assert Game.get_match!(match.id).player_picks == []
  end

  test "historical 5v5 reviews keep player perspective and never expose reorder controls", %{conn: conn} do
    player = create_player!()
    opponent = create_player!()
    hero = Game.create_hero!(%{name: "Champion"}, player, strong_avatar(), base_skills())
    enemy = Game.create_hero!(%{name: "Challenger"}, opponent, weak_avatar(), base_skills())

    match =
      match(player, opponent, %{player_picks: [hero.id], opponent_picks: [enemy.id]})
      |> Ecto.Changeset.change(team_size: 5)
      |> Moba.Repo.update!()

    battle =
      Engine.create_match_battle!(%{
        attacker: enemy,
        attacker_player: opponent,
        defender: hero,
        defender_player: player,
        match: match
      })

    Game.Matches.update!(match, %{phase: "scored", winner_id: player.id})
    {:ok, view, _} = live(log_in_player(conn, player_id: player.id), "/matches/#{match.id}")
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
    refute has_element?(view, "[data-lineup-grip], #start-match-button")
    refute has_element?(view, "#picks-card")
    assert has_element?(view, "#opponent-hero-#{enemy.id} [data-defeated=true]", "Fallen")
    assert has_element?(view, "#hero-#{hero.id} [data-defeated=false]")

    view |> element("#match-details-toggle") |> render_click()
    assert has_element?(view, "#battle-summary-#{battle.id}")
    refute has_element?(view, "#battle-review-#{battle.id}")

    spectator = create_player!()
    {:ok, watching, _} = live(log_in_player(conn, player_id: spectator.id), "/matches/#{match.id}")
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
