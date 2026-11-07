defmodule MobaWeb.V2.InvokeModernLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    hero = create_base_hero()
    conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
    %{conn: conn, hero: hero}
  end

  test "creation loads all choices for browser-only selection", %{conn: conn} do
    {:ok, view, _} = live(conn, "/new/solo")
    assert has_element?(view, "#invoke-modern[phx-update=ignore][data-creation]")
    assert has_element?(view, "#invoke-hero-name", "Juggernaut")
    refute has_element?(view, "#create-bar header > strong")
    refute has_element?(view, "#invoke-modern [phx-click], #invoke-modern [phx-change]")

    for avatar <- Game.list_creation_avatars([]) do
      assert has_element?(view, "#pick-avatar-#{avatar.id}[data-invoke-action=avatar]")
    end

    for skill <- Game.list_creation_skills(1) do
      assert has_element?(view, "#invoke-custom-skills #pick-skill-#{skill.id}[data-invoke-action=skill]")
    end

    assert has_element?(view, "#invoke-build-footer #create-button[data-invoke-action=create]")
    assert has_element?(view, ".invoke-base-stats [data-stat=health] .ui-heart")
    assert has_element?(view, ".invoke-attributes [data-stat=offense] .ui-fist")
  end

  test "the final browser choice is validated and creates the selected hero", %{conn: conn, hero: hero} do
    {:ok, view, _} = live(conn, "/new/solo")
    avatar = Game.list_creation_avatars([]) |> List.first()
    {skills, _} = Game.skill_build_for(avatar.role, 0)

    render_hook(view, "create", %{
      avatar: to_string(avatar.id),
      skills: Enum.map(skills, &to_string(&1.id)),
      name: "Forge Knight"
    })

    assert_redirect(view, "/training?solo=true")
    created = Game.get_player!(hero.player_id).current_pve_hero_id |> Game.get_hero!()
    assert created.name == "Forge Knight"
    assert created.avatar.code == avatar.code
    assert length(created.skills) == 4
  end

  test "invalid or duplicate choices cannot create a record", %{conn: conn, hero: hero} do
    {:ok, view, _} = live(conn, "/new/solo")
    avatar = Game.list_creation_avatars([]) |> List.first()
    skills = Game.list_creation_skills(1) |> Enum.take(3) |> Enum.map(&to_string(&1.id))
    params = %{avatar: to_string(avatar.id), skills: skills, name: hero.player.user.username}

    for invalid <- [
          %{params | avatar: "invalid"},
          %{params | skills: [hd(skills), hd(skills), hd(skills)]},
          %{params | skills: ["invalid"]},
          %{params | name: "x"},
          %{params | skills: "invalid"}
        ] do
      render_hook(view, "create", invalid)
      assert Game.get_player!(hero.player_id).current_pve_hero_id == hero.id
    end
  end

  test "name availability is checked on creation", %{conn: conn, hero: hero} do
    other = create_base_hero()
    {:ok, view, _} = live(conn, "/new/solo")
    avatar = Game.list_creation_avatars([]) |> List.first()
    {skills, _} = Game.skill_build_for(avatar.role, 0)

    render_hook(view, "create", %{
      avatar: to_string(avatar.id),
      skills: Enum.map(skills, &to_string(&1.id)),
      name: other.player.user.username
    })

    assert Game.get_player!(hero.player_id).current_pve_hero_id == hero.id
  end

  test "every unlocked skill is provided when the page loads", %{conn: conn, hero: hero} do
    Enum.each(Game.list_unlockable_skills(), &Accounts.Unlocks.create_unlock!(hero.player.user, &1.code))
    available = Game.list_creation_skills(1, Accounts.unlocked_codes_for(Accounts.get_user!(hero.player.user_id)))
    {:ok, view, _} = live(conn, "/new/solo")
    for skill <- available, do: assert(has_element?(view, "#invoke-custom-skills #pick-skill-#{skill.id}"))

    assert length(available) ==
             view
             |> element("#invoke-custom-skills")
             |> render()
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("button")
             |> Enum.count()
  end

  test "guests add starter builds locally before submitting the full roster" do
    {:ok, view, _} = live(Phoenix.ConnTest.build_conn(), "/start")
    assert has_element?(view, "#invoke-hero-name", "Juggernaut")
    assert has_element?(view, "#create-button[type=button]:not([disabled])", "Add to roster")
    assert has_element?(view, "#team-draft-launch[action='/start'][method=post] input[name=_csrf_token]")
    assert has_element?(view, "#team-draft-launch input[name=roster][value='[]']")
    assert has_element?(view, "#team-draft-begin[disabled]")
  end
end
