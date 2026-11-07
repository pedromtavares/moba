defmodule MobaWeb.V2.LibraryLiveTest do
  use MobaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    player = create_player!()
    conn = log_in_player(conn, player_id: player.id)
    {:ok, view, _} = live(conn, "/library")
    %{view: view}
  end

  test "the Library has three icon tabs and opens on Avatars", %{view: view} do
    assert has_element?(view, "#manual-title", "Library")
    assert has_element?(view, "#manual-heading .manual-heading-description", "Refine your strategy.")
    assert has_element?(view, "#library[phx-hook=ManualCodex][phx-update=ignore]")

    for {key, label, icon} <- [
          {"avatars", "Avatars", "profile"},
          {"skills", "Skills", "manual"},
          {"items", "Items", "catalog-items"}
        ] do
      assert has_element?(view, "#library-tab-#{key}[role=tab][aria-controls=manual-#{key}]", label)
      assert has_element?(view, "#library-tab-#{key} img[src$='/#{icon}.webp']")
      assert has_element?(view, "#manual-#{key}[role=tabpanel][aria-labelledby=library-tab-#{key}]")
    end

    assert has_element?(view, "#library-tab-avatars[aria-selected=true]")
    assert has_element?(view, "#manual-avatars:not([hidden])")
    assert has_element?(view, "#manual-skills[hidden]")
    assert has_element?(view, "#manual-items[hidden]")
    refute has_element?(view, "#manual-wiki, #faq-tab, #training-tab, #arena-tab, .faq-question")
  end

  test "a guest can browse the Items tab without a hero or transaction controls", %{conn: conn} do
    guest = Game.create_player!(%{})
    {:ok, view, _} = live(log_in_player(conn, player_id: guest.id), "/library")

    assert has_element?(view, "#library-tab-items[aria-controls=manual-items]")
    assert has_element?(view, "#manual-items .shop-detail #library-item-detail-boots_of_speed:not([hidden])")
    assert has_element?(view, "#manual-items #library-shop-category-normal[aria-pressed=true]", "400")

    for rarity <- ~w(normal rare epic legendary) do
      assert has_element?(view, "#manual-items .shop-shelf[data-rarity=#{rarity}] .shop-tile img[data-toggle=tooltip]")
    end

    assert has_element?(
             view,
             "#manual-items [data-code=octarine_core][aria-controls=library-item-detail-octarine_core]"
           )

    assert has_element?(view, "#library-item-detail-octarine_core[hidden] .item-tooltip[data-rarity=epic]")
    assert has_element?(view, "#library-item-detail-boots_of_speed [data-stat=base_speed]")

    refute has_element?(view, "#shop-modal, #manual-items :is(.shop-inventory, .shop-wallet, [phx-click], form)")
  end

  test "the avatar browser preloads the entire roster, growth stats and ultimate ranks", %{view: view} do
    document = render(view) |> LazyHTML.from_fragment()
    assert Enum.count(LazyHTML.query(document, "#manual-avatars [data-manual-pick=avatar]")) == 24
    assert has_element?(view, "#manual-avatar-juggernaut:not([hidden]) h2", "Juggernaut")
    assert has_element?(view, "#manual-avatar-juggernaut [data-stat=health] dd small", "/ level")
    assert has_element?(view, "#manual-ultimate-juggernaut-rank-1:not([hidden]) .skill-tooltip", "Omnislash")
    assert has_element?(view, "#manual-ultimate-juggernaut-rank-3[hidden] .skill-tooltip", "Omnislash")
  end

  test "the skill browser exposes all normal skills and every rank without server events", %{view: view} do
    document = render(view) |> LazyHTML.from_fragment()
    assert Enum.count(LazyHTML.query(document, "#manual-skills [data-manual-pick=skill]")) == 24

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
