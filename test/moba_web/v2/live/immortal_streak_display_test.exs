defmodule MobaWeb.V2.ImmortalStreakDisplayTest do
  use MobaWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Moba.Game.Matches
  alias MobaWeb.V2.Components.GameHelpers, as: GH

  test "Arena explains the debuff beneath 5v5, using the manual's wording, including when resuming", %{conn: conn} do
    player = create_player!(%{current_immortal_streak: 7})
    opponent = create_player!()
    conn = log_in_player(conn, player_id: player.id)
    {:ok, view, _} = live(conn, "/arena")

    assert has_element?(
             view,
             ".arena-play-5v5 > #enter-arena-button + #arena-immortal-streak-debuff",
             "−7.0% Hero Stats"
           )

    assert has_element?(view, "#arena-immortal-streak-debuff[data-toggle=tooltip][tabindex='0']")
    refute has_element?(view, ".arena-cinematic-heading .immortal-streak-debuff")
    refute has_element?(view, ".arena-play-1v1 .immortal-streak-debuff")
    assert_tooltip(view, "#arena-immortal-streak-debuff")

    {:ok, manual, _} = live(conn, "/library")
    assert has_element?(manual, ".faq-answer", GH.immortal_streak_debuff_description())

    match(player, opponent, [], [])
    {:ok, resume, _} = live(conn, "/arena")
    assert has_element?(resume, ".arena-play-5v5 > #resume-arena-match + #arena-immortal-streak-debuff")
    assert_tooltip(resume, "#arena-immortal-streak-debuff")
  end

  test "5v5 lineup and picker stats include the streak reduction with the engine's rounding", %{conn: conn} do
    player = create_player!(%{current_immortal_streak: 7})
    opponent = create_player!(%{current_immortal_streak: 3})
    hero = ready_hero(player)
    enemy = ready_hero(opponent)
    match = match(player, opponent, [hero.id], [enemy.id])
    {:ok, view, _} = live(log_in_player(conn, player_id: player.id), "/matches/#{match.id}")

    assert has_element?(
             view,
             ".match-lineup .squad-panel-heading #match-player-streak-debuff",
             "Immortal Streak · −7.0% Hero Stats"
           )

    assert has_element?(view, ".match-enemy .squad-panel-heading #match-opponent-streak-debuff", "−3.0% Hero Stats")
    assert_tooltip(view, "#match-player-streak-debuff")
    assert_tooltip(view, "#match-opponent-streak-debuff")

    assert_stats(view, "#hero-#{hero.id}", hero, 7)
    assert_stats(view, "#opponent-hero-#{enemy.id}", enemy, 3)
    assert_stats(view, "#available-hero-#{hero.id}", hero, 7)
    assert Game.get_hero!(hero.id).total_hp == hero.total_hp
  end

  test "no streak shows no debuff and keeps the original stats", %{conn: conn} do
    player = create_player!()
    opponent = create_player!()
    hero = ready_hero(player)
    enemy = ready_hero(opponent)
    match = match(player, opponent, [hero.id], [enemy.id])
    conn = log_in_player(conn, player_id: player.id)
    {:ok, arena, _} = live(conn, "/arena")
    refute has_element?(arena, "#arena-immortal-streak-debuff")

    {:ok, view, _} = live(conn, "/matches/#{match.id}")
    refute has_element?(view, "#match-player-streak-debuff, #match-opponent-streak-debuff")
    assert_stats(view, "#hero-#{hero.id}", hero, 0)
    assert_stats(view, "#opponent-hero-#{enemy.id}", enemy, 0)
  end

  test "match replays keep the recorded debuff and combat stats after the owner changes", %{conn: conn} do
    player = create_player!(%{current_immortal_streak: 10})
    opponent = create_player!()
    hero = ready_hero(player) |> Game.update_hero!(%{atk: 100_000, speed: 100})
    enemy = ready_hero(opponent)
    match = match(player, opponent, [hero.id], [enemy.id])

    battle =
      Engine.create_match_battle!(%{
        attacker: hero,
        attacker_player: player,
        defender: enemy,
        defender_player: opponent,
        match: match
      })

    assert battle.loadouts[to_string(hero.id)]["immortal_streak"] == 10
    Matches.update!(match, %{phase: "scored", winner_id: battle.winner_player_id})
    Game.update_player!(player, %{current_immortal_streak: 20})
    Game.update_hero!(hero, %{total_hp: 9999, atk: 9999})

    {:ok, view, _} = live(log_in_player(conn, player_id: player.id), "/matches/#{match.id}")
    assert has_element?(view, "#match-player-streak-debuff", "−10.0% Hero Stats")
    refute has_element?(view, "#match-player-streak-debuff", "−20.0%")
    assert_stats(view, "#hero-#{hero.id}", hero, 10)
    refute has_element?(view, "#match-opponent-streak-debuff")
  end

  test "the shared roster keeps normal stats outside 5v5 and previews borrowed heroes like the engine" do
    player = create_player!(%{current_immortal_streak: 9})
    other = create_player!()
    hero = ready_hero(player)
    stats = GH.match_hero_stats(hero, other)
    assert stats.hp == hero.total_hp + hero.item_hp - round(0.09 * (hero.total_hp + hero.item_hp))

    html = render_component(&MobaWeb.V2.Components.PvpComponents.roster_hero/1, hero: hero)

    assert html |> LazyHTML.from_fragment() |> LazyHTML.query("[title='Health'] .stat-value") |> LazyHTML.text() ==
             to_string(hero.total_hp + hero.item_hp)
  end

  defp ready_hero(player) do
    create_base_hero(
      %{
        name: "Ready",
        finished_at: DateTime.utc_now(),
        league_tier: 6,
        total_hp: 997,
        total_mp: 203,
        atk: 101,
        power: 17,
        armor: 7,
        speed: 53,
        gold: 10_000
      },
      player
    )
    |> Game.buy_item!(base_item())
  end

  defp match(player, opponent, picks, enemies) do
    Matches.create!(%{
      player_id: player.id,
      opponent_id: opponent.id,
      player_picks: picks,
      opponent_picks: enemies,
      generated_picks: [],
      type: "manual"
    })
  end

  defp assert_tooltip(view, selector) do
    title = view |> element(selector) |> render() |> LazyHTML.from_fragment() |> LazyHTML.attribute("title")
    assert title == [GH.immortal_streak_debuff_description()]
  end

  defp assert_stats(view, selector, hero, streak) do
    for {label, base, item} <- [
          {"Health", :total_hp, :item_hp},
          {"Energy", :total_mp, :item_mp},
          {"Attack", :atk, :item_atk},
          {"Power", :power, :item_power},
          {"Armor", :armor, :item_armor},
          {"Speed", :speed, :item_speed}
        ] do
      total = Map.fetch!(hero, base) + Map.fetch!(hero, item)
      expected = total - round(Moba.immortal_streak_multiplier() * streak * total)
      value = view |> element("#{selector} .game-stat[title='#{label}'] .stat-value") |> render()
      assert value |> LazyHTML.from_fragment() |> LazyHTML.text() |> String.trim() == to_string(expected)
    end
  end
end
