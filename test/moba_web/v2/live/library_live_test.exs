defmodule MobaWeb.V2.LibraryLiveTest do
  use MobaWeb.ConnCase

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    hero = create_base_hero()
    conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
    {:ok, view, _} = live(conn, "/library")
    %{view: view}
  end

  test "preserves the original banner, wiki tabs and copy", %{view: view} do
    assert has_element?(view, "#manual-title", "Game Manual")
    assert has_element?(view, "#manual-heading .manual-heading-description", "Master the rules. Refine your strategy.")
    assert has_element?(view, "#manual-navigation a[href='#faq-tab']", "Frequently Asked Questions")
    assert has_element?(view, "#manual-navigation a[href='#training-tab']", "Training Guide")
    assert has_element?(view, "#manual-navigation a[href='#arena-tab']", "Arena Guide")
    assert has_element?(view, "#faq-tab .faq-answer", "20 different Avatars")
    assert has_element?(view, "#training-tab .faq-answer", "You have 2 chances of beating Roshan")

    assert has_element?(
             view,
             "#arena-tab .faq-answer",
             MobaWeb.V2.Components.GameHelpers.immortal_streak_debuff_description()
           )

    document = render(view) |> LazyHTML.from_fragment()
    assert Enum.count(LazyHTML.query(document, ".faq-question")) == 16
    refute has_element?(view, "#about-tab, #support-tab, #manual-items, [data-manual-panel]")
  end

  test "the avatar browser preloads the entire roster, growth stats and ultimate ranks", %{view: view} do
    document = render(view) |> LazyHTML.from_fragment()
    assert Enum.count(LazyHTML.query(document, "#manual-avatars [data-manual-pick=avatar]")) == 24
    assert has_element?(view, "#manual-avatars[phx-hook=ManualCodex][phx-update=ignore]")
    assert has_element?(view, "#manual-avatar-juggernaut:not([hidden]) h2", "Juggernaut")
    assert has_element?(view, "#manual-avatar-juggernaut [data-stat=health] dd small", "/ level")
    assert has_element?(view, "#manual-ultimate-juggernaut-rank-1:not([hidden]) .skill-tooltip", "Omnislash")
    assert has_element?(view, "#manual-ultimate-juggernaut-rank-3[hidden] .skill-tooltip", "Omnislash")
  end

  test "the skill browser exposes all normal skills and every rank without server events", %{view: view} do
    document = render(view) |> LazyHTML.from_fragment()
    assert Enum.count(LazyHTML.query(document, "#manual-skills [data-manual-pick=skill]")) == 24
    assert has_element?(view, "#manual-skills[phx-hook=ManualCodex][phx-update=ignore]")

    refute has_element?(
             view,
             "#manual-skill-search, .manual-reference-heading, #manual-avatars-title, #manual-skills-title"
           )

    assert has_element?(view, "#manual-skill-ranks-blink_strike-rank-5[hidden] [data-effect=first] dd")

    assert has_element?(
             view,
             "#manual-skill-ranks-blink_strike-tab-4[role=tab][aria-controls='manual-skill-ranks-blink_strike-rank-4']"
           )

    refute has_element?(view, "#manual-skills [phx-click], #manual-avatars [phx-click]")
  end
end
