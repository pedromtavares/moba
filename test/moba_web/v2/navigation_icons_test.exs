defmodule MobaWeb.V2.NavigationIconsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias MobaWeb.V2.Components.LayoutComponents

  test "registered admin navigation keeps named destinations with local custom emblems" do
    player = %{id: 42, user_id: 7, user: %{is_admin: true}}

    document =
      render_component(&LayoutComponents.sidebar/1, current_player: player, sidebar_code: "arena", preview: true)
      |> LazyHTML.from_fragment()

    for {label, symbol} <- [
          {"Base", "base"},
          {"Arena", "arena"},
          {"Profile", "profile"},
          {"Tavern", "tavern"},
          {"Community", "community"},
          {"Library", "manual"},
          {"Admin", "admin"}
        ] do
      icon = LazyHTML.query(document, "#game-sidebar a[aria-label='#{label}'] img.nav-emblem[aria-hidden=true]")
      assert LazyHTML.attribute(icon, "src") == ["/images/navigation/#{symbol}.webp"]
    end

    assert LazyHTML.attribute(LazyHTML.query(document, "#game-sidebar a.active"), "aria-label") == ["Arena"]
    assert LazyHTML.attribute(LazyHTML.query(document, "#game-sidebar i"), "class") == []

    for label <- ["Base", "Arena", "Profile", "Tavern", "Community", "Library"] do
      link = LazyHTML.query(document, "#game-sidebar a[aria-label='#{label}']")
      assert LazyHTML.attribute(link, "data-sidebar-hotkey") == []
      assert LazyHTML.attribute(link, "aria-keyshortcuts") == []
      assert LazyHTML.query(link, ".sidebar-label kbd") |> Enum.empty?()
      assert LazyHTML.attribute(link, "data-phx-link") == ["redirect"]
    end

    assert LazyHTML.attribute(LazyHTML.query(document, "#game-sidebar a[aria-label=Admin]"), "data-sidebar-hotkey") ==
             []
  end

  test "guest navigation shows the locked Arena and registration action without Community or Library" do
    player = %{id: 42, user_id: nil, user: nil}

    document =
      render_component(&LayoutComponents.sidebar/1, current_player: player, preview: true)
      |> LazyHTML.from_fragment()

    locked = LazyHTML.query(document, "#game-sidebar .no-action")
    assert LazyHTML.attribute(locked, "aria-label") == ["Arena locked: create an account to play"]
    assert LazyHTML.attribute(locked, "data-sidebar-hotkey") == []
    assert LazyHTML.attribute(LazyHTML.query(document, "#create-account-link"), "data-sidebar-hotkey") == []
    assert LazyHTML.attribute(LazyHTML.query(document, "#create-account-link"), "href") == ["/users/register"]

    assert LazyHTML.attribute(LazyHTML.query(document, "#create-account-link .nav-emblem"), "src") == [
             "/images/navigation/join.webp"
           ]

    assert LazyHTML.attribute(LazyHTML.query(document, "#game-sidebar a[aria-label=Admin]"), "href") == []
    assert Enum.empty?(LazyHTML.query(document, "#game-sidebar a:is([aria-label=Community], [aria-label=Library])"))
  end

  test "mobile navigation distinguishes Training from Base with named raster controls" do
    player = %{id: 42, user_id: 7, hero_collection: [%{}]}

    document =
      render_component(&LayoutComponents.mobile_navigation/1,
        current_player: player,
        current_hero: %{finished_at: nil},
        preview: true
      )
      |> LazyHTML.from_fragment()

    for {label, image} <- [{"Training", "training"}, {"Base", "base"}, {"Arena", "arena"}, {"Profile", "profile"}] do
      icon = LazyHTML.query(document, "#topnav a[aria-label='#{label}'] img.nav-emblem")
      assert LazyHTML.attribute(icon, "src") == ["/images/navigation/#{image}.webp"]
    end
  end
end
