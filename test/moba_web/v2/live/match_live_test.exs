defmodule MobaWeb.V2.MatchLiveTest do
  use MobaWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Moba.Game.Matches

  test "renders the v2 match and lets the player pick heroes", %{conn: conn} do
    player = create_player!(%{pvp_tier: 1})
    opponent = create_player!(%{pvp_tier: 1})
    skills = base_skills()

    player_heroes =
      for index <- 1..5 do
        Game.create_hero!(%{name: "Player #{index}"}, player, strong_avatar(), skills)
      end

    opponent_heroes =
      for index <- 1..5 do
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
      |> init_test_session(player_id: player.id)

    first_hero = List.first(player_heroes)

    {:ok, view, _html} = live(conn, "/matches/#{match.id}")
    assert has_element?(view, "#match-hud #winner-card.match-command")

    assert has_element?(
             view,
             ".match-lineup .squad-panel-heading #edit-teams-button[href='/arena/edit?match_id=#{match.id}']"
           )

    assert has_element?(view, "#picks-card.match-picker")
    refute has_element?(view, "#match-return-to-arena")
    refute has_element?(view, ".stats-footer")
    render_click(view, "hero-tab", %{"type" => "trained"})
    render_click(view, "pick-hero", %{"id" => first_hero.id})
    assert has_element?(view, "#hero-#{first_hero.id}")
  end

  test "renders team cards with wrapped avatars on the teams tab", %{conn: conn} do
    player = create_player!(%{pvp_tier: 1})
    opponent = create_player!(%{pvp_tier: 1})
    skills = base_skills()

    player_heroes =
      for index <- 1..5 do
        Game.create_hero!(%{name: "Player #{index}"}, player, strong_avatar(), skills)
      end

    opponent_heroes =
      for index <- 1..5 do
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
      |> init_test_session(player_id: player.id)

    {:ok, view, _html} = live(conn, "/matches/#{match.id}")

    assert has_element?(view, "#pick-team-#{team.id}")

    for hero <- player_heroes do
      assert has_element?(
               view,
               "#pick-team-#{team.id} img[src='#{MobaWeb.V2.Components.GameHelpers.image_url(hero.avatar)}']"
             )
    end
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
      |> init_test_session(player_id: player.id)

    Matches.update!(match, %{phase: "scored", winner_id: battle.winner_player_id})

    {:ok, view, _html} = live(conn, "/matches/#{match.id}")

    player_avatar = MobaWeb.V2.Components.GameHelpers.image_url(player_hero.avatar)
    opponent_avatar = MobaWeb.V2.Components.GameHelpers.image_url(opponent_hero.avatar)

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
      for index <- 1..5 do
        Game.create_hero!(%{name: "Player #{index}"}, player, strong_avatar(), skills)
      end

    opponent_heroes =
      for index <- 1..5 do
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
      |> init_test_session(player_id: player.id)

    {:ok, view, _html} = live(conn, "/matches/#{match.id}")

    assert has_element?(view, "#picks-card")
    refute has_element?(view, "[phx-hook=TutorialStep]")

    render_click(view, "finish-tutorial", %{})

    assert Game.get_player!(player.id).tutorial_step == 39
    refute has_element?(view, "[phx-hook=TutorialStep]")
  end
end
