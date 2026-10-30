defmodule MobaWeb.V2.CommunityLiveTest do
  use MobaWeb.ConnCase

  import Phoenix.LiveViewTest

  setup do
    for key <- ["pve_ranking", "season_ranking"], do: Cachex.del(:game_cache, key)

    on_exit(fn ->
      for key <- ["pve_ranking", "season_ranking"], do: Cachex.del(:game_cache, key)
    end)

    :ok
  end

  test "rankings load only when selected and inactive panels are not rendered", %{conn: conn} do
    hero = create_base_hero(%{finished_at: Timex.now(), pve_ranking: 1})
    conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
    {:ok, view, _} = live(conn, "/community")

    assert has_element?(view, "#community-online")
    refute has_element?(view, "#community-pvp")
    refute has_element?(view, "#community-pve")
    assert Cachex.get(:game_cache, "pve_ranking") == {:ok, nil}
    assert Cachex.get(:game_cache, "season_ranking") == {:ok, nil}

    view |> element("#show-pve-link") |> render_click()
    assert has_element?(view, "#community-pve .hero-stats")
    refute has_element?(view, "#community-online")
    refute has_element?(view, "#community-pvp")
    assert {:ok, [_ | _]} = Cachex.get(:game_cache, "pve_ranking")
    assert Cachex.get(:game_cache, "season_ranking") == {:ok, nil}

    view |> element("#show-online-link") |> render_click()
    view |> element("#show-pvp-link") |> render_click()
    assert has_element?(view, "#community-pvp")
    refute has_element?(view, "#community-pve")
    refute has_element?(view, "#community-online")
    assert {:ok, ranking} = Cachex.get(:game_cache, "season_ranking")
    assert is_list(ranking)
  end

  test "renders community and switches ranking tabs", %{conn: conn} do
    hero = create_base_hero(%{finished_at: Timex.now(), pve_ranking: 1})

    conn =
      conn
      |> log_in_user(hero.player.user)
      |> put_session(:player_id, hero.player_id)

    {:ok, view, html} = live(conn, "/community")

    assert html =~ "Message Board"
    assert html =~ "Updates"
    assert has_element?(view, "#community-message-form")
    assert has_element?(view, "#show-online-link")

    render_click(view, "show-pvp", %{})
    assert has_element?(view, "#show-pvp-link.active")

    render_click(view, "show-pve", %{})
    assert has_element?(view, "#show-pve-link.active")
    assert has_element?(view, ".hero-stats .text-danger[title='Health']")
    assert has_element?(view, ".hero-stats .text-orange[title='Speed']")
    assert has_element?(view, "#skill-#{hero.skills |> List.first() |> Map.fetch!(:id)}-#{hero.id}")
    assert has_element?(view, ".items-container")
  end

  test "creates a community message", %{conn: conn} do
    hero = create_base_hero()

    conn =
      conn
      |> log_in_user(hero.player.user)
      |> put_session(:player_id, hero.player_id)

    {:ok, view, _html} = live(conn, "/community")

    html =
      view
      |> form("#community-message-form", %{"message" => %{"body" => "Parity audit message"}})
      |> render_submit()

    assert html =~ "Message Board"

    [message | _] = Accounts.latest_messages("community", "general", 1)
    assert message.body == "Parity audit message"
  end

  test "preview keeps message and update content, sends messages, and switches tabs", %{conn: conn} do
    hero = create_base_hero(%{finished_at: Timex.now(), pve_ranking: 1})

    attrs = %{
      channel: "community",
      author: hero.player.user.username,
      user_id: hero.player.user_id,
      tier: hero.player.pve_tier
    }

    message =
      Accounts.create_message!(
        Map.merge(attrs, %{topic: "general", body: "A community question\nWith another paragraph"})
      )

    update =
      Accounts.create_message!(
        Map.merge(attrs, %{
          topic: "updates",
          title: "Development news",
          body: "All announcement details remain readable."
        })
      )

    conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
    {:ok, view, _} = live(conn, "/community")

    assert has_element?(view, "#community-message-#{message.id} .inbox-item-text", "A community question")
    assert has_element?(view, "#community-message-#{message.id} .inbox-item-text", "With another paragraph")
    assert has_element?(view, "#community-update-#{update.id}", "Development news")
    assert has_element?(view, "#community-update-#{update.id} .community-update-body", update.body)
    assert has_element?(view, "#community-message-form button[type=submit]")
    assert has_element?(view, "#show-online-link[aria-selected=true]")

    view
    |> form("#community-message-form", %{"message" => %{"body" => "Sent from the new composer"}})
    |> render_submit()

    [sent] = Accounts.latest_messages("community", "general", 1)
    assert sent.body == "Sent from the new composer"
    assert has_element?(view, "#community-message-#{sent.id} .inbox-item-text", sent.body)

    view |> element("#show-pvp-link") |> render_click()
    assert has_element?(view, "#show-pvp-link[aria-selected=true]")
    refute has_element?(view, "#community-pvp.d-none")
    assert has_element?(view, "#show-online-link[aria-selected=false]")

    view |> element("#show-pve-link") |> render_click()
    assert has_element?(view, "#show-pve-link[aria-selected=true]")
    assert has_element?(view, "#community-pve .hero-stats")
    assert has_element?(view, "#community-pve span.game-stat[title^='Total farm:']")
    refute has_element?(view, "#community-pve button, #community-pvp button")
  end
end
