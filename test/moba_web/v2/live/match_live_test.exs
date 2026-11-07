defmodule MobaWeb.V2.MatchLiveTest do
  use MobaWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Moba.Game.Matches

  test "renders the v2 match and lets the player pick heroes", %{conn: conn} do
    player = create_player!(%{pvp_tier: 1})
    opponent = create_player!(%{pvp_tier: 1})
    skills = base_skills()

    player_heroes =
      for index <- 1..3 do
        Game.create_hero!(
          %{name: "Player #{index}", finished_at: Timex.now(), league_tier: 6},
          player,
          strong_avatar(),
          skills
        )
      end

    opponent_heroes =
      for index <- 1..3 do
        Game.create_hero!(%{name: "Opponent #{index}"}, opponent, weak_avatar(), skills)
      end

    match =
      Matches.create!(%{
        player_id: player.id,
        opponent_id: opponent.id,
        player_picks: [],
        opponent_picks: Enum.map(opponent_heroes, & &1.id),
        generated_picks: [],
        type: "manual"
      })

    conn =
      conn
      |> log_in_player(player_id: player.id)

    first_hero = List.first(player_heroes)

    {:ok, view, _html} = live(conn, "/matches/#{match.id}")
    assert has_element?(view, "#match-hud.arena-preparation")
    assert has_element?(view, ".match-lineup header h2", "Your lineup")
    assert has_element?(view, ".match-enemy header span", "Opponent lineup")
    assert has_element?(view, "#edit-teams-button[href='/arena/edit?match_id=#{match.id}']")
    assert has_element?(view, "#picks-card.match-picker")
    assert has_element?(view, "#start-match-button[disabled]")
    refute has_element?(view, "#available-heroes-button")
    refute has_element?(view, "[aria-label='Hero source']")
    render_click(view, "pick-hero", %{"id" => first_hero.id})
    assert has_element?(view, "#hero-#{first_hero.id}")
  end

  test "renders team cards with wrapped avatars on the teams tab", %{conn: conn} do
    player = create_player!(%{pvp_tier: 1})
    opponent = create_player!(%{pvp_tier: 1})
    skills = base_skills()

    player_heroes =
      for index <- 1..3 do
        Game.create_hero!(
          %{name: "Player #{index}", finished_at: Timex.now(), league_tier: 6},
          player,
          strong_avatar(),
          skills
        )
      end

    opponent_heroes =
      for index <- 1..3 do
        Game.create_hero!(%{name: "Opponent #{index}"}, opponent, weak_avatar(), skills)
      end

    team = Game.create_team!(%{name: "Elite", player_id: player.id, pick_ids: Enum.map(player_heroes, & &1.id)})

    match =
      Matches.create!(%{
        player_id: player.id,
        opponent_id: opponent.id,
        player_picks: [],
        opponent_picks: Enum.map(opponent_heroes, & &1.id),
        generated_picks: [],
        type: "manual"
      })

    conn =
      conn
      |> log_in_player(player_id: player.id)

    {:ok, view, _html} = live(conn, "/matches/#{match.id}")

    assert has_element?(view, "#pick-team-#{team.id}")

    for hero <- player_heroes do
      assert has_element?(
               view,
               "#pick-team-#{team.id} img[src='#{MobaWeb.V2.Components.GameHelpers.image_url(hero.avatar)}']"
             )
    end

    view |> element("#pick-team-#{team.id}") |> render_click()

    assert has_element?(view, "#match-hud[data-playback=false] #start-match-button[data-game-fullscreen]")

    for hero <- player_heroes do
      assert has_element?(view, ".match-lineup .lineup-list #hero-#{hero.id} .roster-actions")
    end

    [first_hero, middle_hero, last_hero] = player_heroes
    assert has_element?(view, "#hero-#{first_hero.id} [data-lineup-grip]")

    view
    |> element("#match-hud")
    |> render_hook("reorder-lineup", %{
      "lineup_id" => match.id,
      "hero_ids" => [first_hero.id, last_hero.id, middle_hero.id]
    })

    assert has_element?(view, ".lineup-list > :nth-child(2)#hero-#{last_hero.id}")

    view
    |> element("#lineup-unpick-#{last_hero.id}[aria-label='Remove #{last_hero.name} from lineup']")
    |> render_click()

    refute has_element?(view, ".match-lineup #hero-#{last_hero.id}")
    assert has_element?(view, "#match-empty-slot-3")
  end

  test "selecting a saved team loads its available heroes in order even when incomplete", %{conn: conn} do
    player = create_player!(%{pvp_tier: 1})
    opponent = create_player!()

    [first, second, third, archived, foreign] =
      for {owner, name} <- [
            {player, "First"},
            {player, "Second"},
            {player, "Third"},
            {player, "Archived"},
            {opponent, "Foreign"}
          ] do
        Game.create_hero!(
          %{name: name, finished_at: Timex.now(), league_tier: 6},
          owner,
          strong_avatar(),
          base_skills()
        )
      end

    partial = Game.create_team!(%{name: "Partial", player_id: player.id, pick_ids: [third.id, first.id]})

    stale =
      Game.create_team!(%{name: "Stale", player_id: player.id, pick_ids: [second.id, archived.id, first.id]})

    unavailable = Game.create_team!(%{name: "Unavailable", player_id: player.id, pick_ids: [archived.id]})

    match =
      Matches.create!(%{
        player_id: player.id,
        opponent_id: opponent.id,
        player_picks: [],
        opponent_picks: [],
        generated_picks: [],
        type: "manual"
      })

    {:ok, view, _} = live(log_in_player(conn, player_id: player.id), "/matches/#{match.id}")

    view |> element("#pick-team-#{partial.id}") |> render_click()

    for {hero, position} <- Enum.with_index([third, first], 1) do
      assert has_element?(view, ".match-lineup .lineup-list > :nth-child(#{position})#hero-#{hero.id}")
    end

    assert has_element?(view, "#match-empty-slot-3")
    assert has_element?(view, "#start-match-button[disabled]")
    refute Matches.valid_picks?(match, player, [third.id, first.id])

    # Availability must be checked at selection time, not from the mounted team snapshot.
    Game.update_hero!(archived, %{archived_at: Timex.now()})
    view |> element("#pick-team-#{stale.id}") |> render_click()
    assert has_element?(view, ".match-lineup .lineup-list > :nth-child(1)#hero-#{second.id}")
    assert has_element?(view, ".match-lineup .lineup-list > :nth-child(2)#hero-#{first.id}")

    refute has_element?(
             view,
             ".match-lineup #hero-#{archived.id}, .match-lineup #hero-#{foreign.id}, .match-lineup #hero-#{third.id}"
           )

    assert has_element?(view, "#match-empty-slot-3")
    assert has_element?(view, "#game-feedback-info", "Choose replacements for the open slots.")

    view |> element("#pick-team-#{unavailable.id}") |> render_click()
    assert has_element?(view, "#game-feedback-error", "This team has no available heroes.")
    assert has_element?(view, ".match-lineup #hero-#{second.id}")
    assert has_element?(view, ".match-lineup #hero-#{first.id}")
    assert Game.get_match!(match.id).player_picks == []
  end

  test "renders battle reviews from player and opponent pick perspective", %{conn: conn} do
    player = create_player!(%{pvp_tier: 1})
    opponent = create_player!(%{pvp_tier: 1})
    skills = base_skills()

    opponent_avatar =
      strong_avatar()
      |> Ecto.Changeset.change(code: "review_opponent", image: %{file_name: "opponent-review.webp", updated_at: nil})
      |> Moba.Repo.update!()

    player_hero = Game.create_hero!(%{name: "Player Hero"}, player, alternate_avatar(), skills)
    opponent_hero = Game.create_hero!(%{name: "Opponent Hero"}, opponent, opponent_avatar, skills)

    match =
      Matches.create!(%{
        player_id: player.id,
        opponent_id: opponent.id,
        player_picks: [player_hero.id],
        opponent_picks: [opponent_hero.id],
        generated_picks: [],
        type: "manual"
      })

    battle =
      Engine.create_match_battle!(%{
        attacker: opponent_hero,
        attacker_player: opponent,
        defender: player_hero,
        defender_player: player,
        match: match
      })
      |> Engine.auto_finish_battle!()

    conn =
      conn
      |> log_in_player(player_id: player.id)

    Matches.update!(match, %{phase: "scored", winner_id: battle.winner_player_id})

    {:ok, view, _html} = live(conn, "/matches/#{match.id}")

    player_avatar = MobaWeb.V2.Components.GameHelpers.image_url(player_hero.avatar)
    opponent_avatar = MobaWeb.V2.Components.GameHelpers.image_url(opponent_hero.avatar)

    assert has_element?(view, ".match-center > #match-scoreboard[data-complete=true]", "Heroes defeated")

    defeated_card =
      if battle.winner_player_id == player.id,
        do: "#opponent-hero-#{opponent_hero.id}",
        else: "#hero-#{player_hero.id}"

    assert has_element?(view, "#{defeated_card} .roster-hero[data-defeated=true][data-falling=false]")

    assigns = %{
      preview: true,
      current_player: player,
      match: Game.get_match!(match.id),
      picked_heroes: [player_hero],
      battles: [battle],
      starting: false,
      show_battle_details: false
    }

    for {tick, defeated, falling} <- [{0, false, false}, {1, true, true}, {15, true, false}] do
      document =
        render_component(&MobaWeb.V2.MatchLive.modern/1, Map.put(assigns, :tick, tick))
        |> LazyHTML.from_fragment()

      assert document
             |> LazyHTML.query("#{defeated_card} .roster-hero[data-defeated=#{defeated}][data-falling=#{falling}]")
             |> Enum.count() == 1
    end

    assert has_element?(
             view,
             ~s|#battle-summary-#{battle.id} .match-summary-hero:first-child img[src="#{player_avatar}"]|
           )

    assert has_element?(
             view,
             ~s|#battle-summary-#{battle.id} .match-summary-hero:last-child img[src="#{opponent_avatar}"]|
           )

    assert has_element?(view, ".match-center #match-battles + #match-return-to-arena[href='/arena']", "Return to arena")

    view |> element("#match-details-toggle") |> render_click()
    assert has_element?(view, ".match-center #match-return-to-arena[href='/arena']")

    view |> element("#match-return-to-arena") |> render_click()
    assert_redirect(view, "/arena")
  end

  test "match page completes retired arena lessons automatically", %{conn: conn} do
    player = create_player!(%{pvp_tier: 1, tutorial_step: 31})
    opponent = create_player!(%{pvp_tier: 1})
    skills = base_skills()

    _player_heroes =
      for index <- 1..3 do
        Game.create_hero!(
          %{name: "Player #{index}", finished_at: Timex.now(), league_tier: 6},
          player,
          strong_avatar(),
          skills
        )
      end

    opponent_heroes =
      for index <- 1..3 do
        Game.create_hero!(%{name: "Opponent #{index}"}, opponent, weak_avatar(), skills)
      end

    match =
      Matches.create!(%{
        player_id: player.id,
        opponent_id: opponent.id,
        player_picks: [],
        opponent_picks: Enum.map(opponent_heroes, & &1.id),
        generated_picks: [],
        type: "manual"
      })

    conn =
      conn
      |> log_in_player(player_id: player.id)

    {:ok, view, _html} = live(conn, "/matches/#{match.id}")

    assert has_element?(view, "#picks-card")
    refute has_element?(view, "[phx-hook=TutorialStep]")

    assert Game.get_player!(player.id).tutorial_step == 31
  end
end
