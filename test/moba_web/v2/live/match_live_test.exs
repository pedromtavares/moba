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
    assert has_element?(view, ~s|#winner-card[phx-hook="EqualHeight"][phx-target="#player-card"]|)
    assert has_element?(view, ~s|#picks-card[phx-hook="EqualHeight"][phx-target="#opponent-heroes-container"]|)
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
    teams_html = view |> element("#teams-heroes") |> render()

    assert length(Regex.scan(~r/class="avatar-container mr-1"/, teams_html)) == 5
  end

  test "renders battle reviews from player and opponent pick perspective", %{conn: conn} do
    player = create_player!(%{pvp_tier: 1})
    opponent = create_player!(%{pvp_tier: 1})
    skills = base_skills()

    player_hero = Game.create_hero!(%{name: "Player Hero"}, player, alternate_avatar(), skills)
    opponent_hero = Game.create_hero!(%{name: "Opponent Hero"}, opponent, strong_avatar(), skills)

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

    {:ok, view, _html} = live(conn, "/matches/#{match.id}")

    review_html = view |> element("#battle-review-#{battle.id}") |> render()
    player_avatar = MobaWeb.V2.Components.GameHelpers.image_url(player_hero.avatar)
    opponent_avatar = MobaWeb.V2.Components.GameHelpers.image_url(opponent_hero.avatar)

    assert has_element?(view, "#battle-review-#{battle.id}")
    assert String.contains?(review_html, player_avatar)
    assert String.contains?(review_html, opponent_avatar)

    {player_index, _} = :binary.match(review_html, player_avatar)
    {opponent_index, _} = :binary.match(review_html, opponent_avatar)

    assert player_index < opponent_index
  end
end
