defmodule MobaWeb.BackendSecurityTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Moba.Repo

  test "visitors cannot change another player's hero through hidden events", %{conn: conn} do
    victim = create_base_hero(%{gold: 10_000, level: 10, skill_levels_available: 1}) |> Game.buy_item!(base_item())
    visitor = create_base_hero()
    {:ok, view, _} = conn |> log_in_player(player_id: visitor.player_id) |> live("/hero/#{victim.id}")
    refute has_element?(view, "#customize-hero")

    for {event, params} <- [
          {"sell", %{"code" => base_item().code}},
          {"buy", %{"code" => alternate_item().code}},
          {"skill", %{"code" => base_skill().code}},
          {"finalize-edit", %{"skill_order" => %{}, "item_order" => %{}}},
          {"set-skin", %{"skin-code" => "default"}},
          {"level", %{}}
        ],
        do: render_click(view, event, params)

    stored = Game.get_hero!(victim.id)
    assert stored.gold == victim.gold
    assert stored.skill_levels_available == victim.skill_levels_available
    assert stored.skill_order == victim.skill_order
    assert Enum.map(stored.items, & &1.id) == Enum.map(victim.items, & &1.id)
    assert stored.skin_id == victim.skin_id
  end

  test "spectators cannot attack or force another player's duel pick", %{conn: conn} do
    first = create_base_hero(%{total_hp: 10_000, total_mp: 1_000})
    second = create_base_hero(%{total_hp: 10_000, total_mp: 1_000})
    spectator = create_base_hero(%{finished_at: Timex.now(), league_tier: 6})
    conn = log_in_player(conn, player_id: spectator.player_id)
    battle = create_basic_battle(first, second)
    {:ok, view, _} = live(conn, "/battles/#{battle.id}")
    render_click(view, "next-turn", %{"skill_id" => "", "item_id" => "", "hero_id" => "#{first.id}"})
    render_click(view, "check-timer", %{})
    assert Engine.get_battle!(battle.id).turns == []

    duel = Game.create_duel!(first.player, second.player, false)
    {:ok, duel_view, _} = live(conn, "/arena/#{duel.id}")
    render_click(duel_view, "pick", %{"id" => "#{spectator.id}"})
    assert Game.get_duel!(duel.id).phase == "player_first_pick"
    assert Game.get_duel!(duel.id).player_first_pick_id == nil
  end

  test "only the current participant can select an eligible duel hero", %{conn: conn} do
    first = create_base_hero(%{finished_at: Timex.now(), league_tier: 6})
    second = create_base_hero(%{finished_at: Timex.now(), league_tier: 6})
    duel = Game.create_duel!(first.player, second.player, false)
    {:ok, view, _} = conn |> log_in_player(player_id: second.player_id) |> live("/arena/#{duel.id}")
    render_click(view, "pick", %{"id" => "#{second.id}"})
    assert Game.get_duel!(duel.id).phase == "player_first_pick"
    Game.pick_duel_hero(duel, first.player, first)
    assert Game.get_duel!(duel.id).player_first_pick_id == first.id
    # Replaying the previous phase cannot make the opponent's next pick.
    Game.pick_duel_hero(duel, first.player, first)
    assert Game.get_duel!(duel.id).opponent_first_pick_id == nil
    render_click(view, "pick", %{"id" => "#{second.id}"})
    assert Game.get_duel!(duel.id).opponent_first_pick_id == second.id
    assert has_element?(view, "#duel-page[data-phase=player_battle]")
  end

  test "registered player ids cannot bypass missing, revoked, or mismatched user tokens", %{conn: conn} do
    hero = create_base_hero()
    missing = conn |> init_test_session(player_id: hero.player_id) |> get("/base")
    assert redirected_to(missing) == "/users/log_in"
    authed = log_in_player(conn, player_id: hero.player_id)
    token = get_session(authed, :user_token)
    MobaWeb.Endpoint.subscribe("users_sessions:#{Base.url_encode64(token)}")

    {:ok, _} =
      Accounts.reset_user_password(hero.player.user, %{
        password: "replacement-password",
        password_confirmation: "replacement-password"
      })

    assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
    refute Accounts.get_user_by_session_token(token)
    assert authed |> get("/base") |> redirected_to() == "/users/log_in"

    other = create_base_hero()
    response = conn |> log_in_user(other.player.user) |> put_session(:player_id, hero.player_id) |> get("/base")
    assert response.assigns.current_player.id == other.player_id
  end

  test "a connected game session checks token validity before mutations", %{conn: conn} do
    hero = create_base_hero()
    conn = log_in_player(conn, player_id: hero.player_id)
    {:ok, view, _} = live(conn, "/hero/#{hero.id}")
    Accounts.delete_user_session_token(get_session(conn, :user_token))
    render_click(view, "sell", %{"code" => base_item().code})
    assert_redirect(view, "/users/log_in")
  end

  test "guest sessions still access training", %{conn: conn} do
    guest = Game.start_guest!("security-guest-#{System.unique_integer([:positive])}", base_avatar(), creation_skills())
    {:ok, view, _} = conn |> init_test_session(player_id: guest.id) |> live("/training")
    assert has_element?(view, "#training-hero-hud") || has_element?(view, ".training")
  end

  test "a guest tab cannot bypass authentication after the player registers", %{conn: conn} do
    guest = Game.start_guest!("adopted-guest-#{System.unique_integer([:positive])}", base_avatar(), creation_skills())
    {:ok, view, _} = conn |> init_test_session(player_id: guest.id) |> live("/training")
    user = create_user()
    Game.update_player!(guest, %{user_id: user.id})
    render_click(view, "show-mine", %{})
    assert_redirect(view, "/users/log_in")
  end

  test "farming cannot be claimed early or started with invalid turns", %{conn: conn} do
    hero = create_base_hero()
    {:ok, view, _} = conn |> log_in_player(player_id: hero.player_id) |> live("/training")
    render_click(view, "select-turns", %{"turns" => "-10"})
    render_click(view, "start-farming", %{"state" => "mining"})
    assert Game.get_hero!(hero.id).pve_state == "alive"
    render_click(view, "select-turns", %{"turns" => "5"})
    render_click(view, "start-farming", %{"state" => "mining"})
    render_click(view, "finish-farming", %{})
    stored = Game.get_hero!(hero.id)
    assert stored.gold == hero.gold
    assert stored.pve_current_turns == hero.pve_current_turns
    assert stored.pve_state == "mining"
    render(view)
  end

  test "duel deletion requires admin status and the same channel", %{conn: conn} do
    hero = create_base_hero()
    other = create_base_hero()
    duel = Game.create_duel!(hero.player, other.player, false)

    message =
      Accounts.create_message!(%{
        body: "Community message",
        author: "Test",
        channel: "community",
        topic: "general",
        user_id: other.player.user_id
      })

    {:ok, view, _} = conn |> log_in_player(player_id: hero.player_id) |> live("/arena/#{duel.id}")
    render_click(view, "delete-message", %{"id" => "#{message.id}"})
    assert Repo.get(Moba.Accounts.Schema.Message, message.id)

    own_channel =
      Accounts.create_message!(%{
        body: "Duel message",
        author: "Test",
        channel: "duel-#{duel.id}",
        topic: "general",
        user_id: other.player.user_id
      })

    render_click(view, "delete-message", %{"id" => "#{own_channel.id}"})
    assert Repo.get(Moba.Accounts.Schema.Message, own_channel.id)
    Repo.update!(Ecto.Changeset.change(hero.player.user, is_admin: true))
    {:ok, admin_view, _} = conn |> log_in_player(player_id: hero.player_id) |> live("/arena/#{duel.id}")
    render_click(admin_view, "delete-message", %{"id" => "#{message.id}"})
    assert Repo.get(Moba.Accounts.Schema.Message, message.id)
    render_click(admin_view, "delete-message", %{"id" => "#{own_channel.id}"})
    refute Repo.get(Moba.Accounts.Schema.Message, own_channel.id)
  end

  test "creation rejects locked avatars and elevated skills at both entry points", %{conn: conn} do
    hero = create_base_hero()
    locked = Game.get_avatar_by_code!("bloodseeker")
    ids = Enum.map(creation_skills(), & &1.id)
    assert Game.invoke_hero(hero.player, %{}, locked.id, ids) == {:error, :invalid_loadout}
    elevated = Game.get_skill_by_code!("decay", true, 5)
    assert Game.creation_loadout(hero.player, base_avatar().id, [elevated.id | tl(ids)]) == {:error, :invalid_loadout}
    response = conn |> get("/start") |> recycle() |> post("/start", %{"avatar" => locked.id, "skills" => ids})
    assert redirected_to(response) == "/start"
    refute get_session(response, :player_id)
    Accounts.create_unlock!(hero.player.user, locked.code)
    assert {:ok, new_hero} = Game.invoke_hero(hero.player, %{}, locked.id, ids)
    assert new_hero.avatar.code == locked.code
  end

  test "3v3 refuses foreign unfinished heroes, duplicates, and spectator changes", %{conn: conn} do
    owner = create_base_hero(%{finished_at: Timex.now(), league_tier: 6})
    opponent = create_base_hero()
    foreign = create_base_hero()

    match =
      Moba.Game.Matches.create!(%{
        player_id: owner.player_id,
        opponent_id: opponent.player_id,
        player_picks: [],
        opponent_picks: [opponent.id],
        generated_picks: [],
        type: "manual"
      })

    {:ok, view, _} = conn |> log_in_player(player_id: owner.player_id) |> live("/matches/#{match.id}")
    render_click(view, "pick-hero", %{"id" => "#{foreign.id}"})
    refute has_element?(view, "#hero-#{foreign.id}")
    render_click(view, "pick-hero", %{"id" => "#{owner.id}"})
    render_click(view, "pick-hero", %{"id" => "#{owner.id}"})
    assert has_element?(view, "#hero-#{owner.id}")
    assert has_element?(view, ".match-lineup header > span", "1 / 3")
    assert Game.start_match(match, owner.player, List.duplicate(owner.id, 5)) == {:error, :invalid_lineup}
    assert Game.start_match(match, foreign.player, [owner.id]) == {:error, :invalid_lineup}
    {:ok, visitor, _} = conn |> log_in_player(player_id: foreign.player_id) |> live("/matches/#{match.id}")
    render_click(visitor, "pick-hero", %{"id" => "#{owner.id}"})
    render_click(visitor, "start", %{})
    assert Game.get_match!(match.id).phase == nil
    assert Game.get_match!(match.id).player_picks == []
  end
end
