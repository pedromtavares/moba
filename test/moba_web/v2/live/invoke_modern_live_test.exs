defmodule MobaWeb.V2.InvokeModernLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    hero = create_base_hero()
    conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
    avatar = Game.list_creation_avatars(Accounts.unlocked_codes_for(hero.player.user)) |> List.first()
    %{conn: conn, hero: hero, avatar: avatar}
  end

  test "role filters preserve all available Avatar choices", %{conn: conn, avatar: avatar} do
    {:ok, view, _} = live(conn, "/invoke")
    assert has_element?(view, "#invoke-modern #invoke-filter-all[aria-pressed=true]")
    assert has_element?(view, "section#invoke-collection .invoke-collection-hero.is-untrained")
    refute has_element?(view, "#invoke-collection summary")
    view |> element("#invoke-filter-#{avatar.role}") |> render_click()
    assert has_element?(view, "#invoke-filter-#{avatar.role}[aria-pressed=true]")
    assert has_element?(view, "#pick-avatar-#{avatar.id}")
    view |> element("#invoke-filter-all") |> render_click()
    assert has_element?(view, "#invoke-filter-all[aria-pressed=true]")

    for available <- Game.list_creation_avatars([]) do
      assert has_element?(view, "#pick-avatar-#{available.id}")
    end
  end

  test "preset selection, name validation and invoking retain the training flow", %{
    conn: conn,
    hero: hero,
    avatar: avatar
  } do
    {:ok, view, _} = live(conn, "/invoke")
    view |> element("#pick-avatar-#{avatar.id}") |> render_click()
    assert has_element?(view, "#invoke-builds")
    assert has_element?(view, ".invoke-base-stats [data-stat=health] .ui-heart")
    assert has_element?(view, ".invoke-attributes [data-stat=offense] .ui-fist")
    assert has_element?(view, "#create-button[disabled]")
    assert has_element?(view, "#skill_#{avatar.ultimate.id}")
    view |> element("#pick-build-0") |> render_click()
    assert has_element?(view, "#pick-build-0[aria-pressed=true]")
    refute has_element?(view, "#create-button[disabled]")
    view |> form("#invoke-name-form", name: "x") |> render_change()
    assert has_element?(view, "#invoke-name-error")
    assert has_element?(view, "#create-button[disabled]")
    view |> form("#invoke-name-form", name: "Forge Knight") |> render_change()
    refute has_element?(view, "#invoke-name-error")
    assert has_element?(view, "#invoke-name-form input[value='Forge Knight']")
    view |> element("#create-button") |> render_click()
    assert_redirect(view, "/training")
    player = Game.get_player!(hero.player_id)
    created = Game.get_hero!(player.current_pve_hero_id)
    assert created.name == "Forge Knight"
    assert created.avatar.code == avatar.code
    assert length(created.skills) == 4
  end

  test "custom skills cap at three, can be removed and survive mode switches", %{conn: conn, avatar: avatar} do
    {:ok, view, _} = live(conn, "/invoke")
    view |> element("#pick-avatar-#{avatar.id}") |> render_click()
    view |> element("#custom-build-button") |> render_click()
    skills = Game.list_creation_skills(1) |> Enum.take(4)

    for skill <- Enum.take(skills, 3) do
      view |> element("#pick-skill-#{skill.id}") |> render_click()
      assert has_element?(view, "#pick-skill-#{skill.id}[aria-pressed=true]")

      assert has_element?(
               view,
               "#pick-skill-#{skill.id} .invoke-energy[aria-label='Energy cost: #{skill.mp_cost || 0}'] .ui-bolt"
             )

      assert has_element?(
               view,
               ".invoke-loadout-slot:has(#skill_#{skill.id}) .invoke-energy[aria-label='Energy cost: #{skill.mp_cost || 0}'] .ui-bolt"
             )
    end

    assert has_element?(
             view,
             ".invoke-ultimate-slot .invoke-energy[aria-label='Energy cost: #{avatar.ultimate.mp_cost || 0}'] .ui-bolt"
           )

    fourth = Enum.at(skills, 3)
    assert has_element?(view, "#pick-skill-#{fourth.id}[aria-disabled=true]")
    view |> element("#pick-skill-#{fourth.id}") |> render_click()
    refute has_element?(view, "#skill_#{fourth.id}")
    first = hd(skills)
    view |> element("#skill_#{first.id}") |> render_click()
    refute has_element?(view, "#pick-skill-#{first.id}[aria-pressed=true]")
    assert has_element?(view, "#create-button[disabled]")
    view |> element("#pick-skill-#{fourth.id}") |> render_click()
    refute has_element?(view, "#create-button[disabled]")
    view |> element("#back-to-builds-button") |> render_click()
    assert has_element?(view, "#skill_#{fourth.id}")
    view |> element("#repick-button") |> render_click()
    assert has_element?(view, "#invoke-avatars")
    refute has_element?(view, "#create-bar")
  end

  test "guest creation retains its POST and selected skill fields", %{avatar: avatar} do
    guest = Phoenix.ConnTest.build_conn()
    {:ok, view, _} = live(guest, "/start")
    assert has_element?(view, "#invoke-start-header h1", "Pick your Avatar")
    refute has_element?(view, "#invoke-collection")
    view |> element("#pick-avatar-#{avatar.id}") |> render_click()
    refute has_element?(view, "#invoke-start-header")
    view |> element("#pick-build-0") |> render_click()
    assert has_element?(view, "#invoke-guest-form[action='/start'][method=post]")
    assert has_element?(view, "#invoke-guest-form input[name=avatar][value='#{avatar.id}']")

    assert Enum.count(
             view
             |> element("#invoke-guest-form")
             |> render()
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("input[name='skills[]']")
           ) == 3

    refute has_element?(view, "#create-button[disabled]")
  end
end
