defmodule MobaWeb.V2.TrainingFarmingLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest

  test "preview farming selects turns, starts, reloads, and claims both resources", %{conn: conn} do
    for {state, tab, resource_field, image} <- [
          {"mining", "mine", :total_gold_farm, "mining"},
          {"meditating", "meditation", :total_xp_farm, "meditation"}
        ] do
      hero = create_base_hero(%{pve_tier: 4, pve_current_turns: 6})
      Game.update_tutorial_step!(hero.player, 20)
      conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
      {:ok, view, _} = live(conn, "/training")
      view |> element("#farm-tab-#{tab}") |> render_click()

      assert has_element?(
               view,
               "#farm-activity[data-activity='#{state}'] img[src='/images/training/#{image}-dark-fantasy.png']"
             )

      assert has_element?(view, "#farm-turn-6[aria-pressed=true]")
      view |> element("#farm-turn-2") |> render_click()
      assert has_element?(view, "#farm-turn-2[aria-pressed=true]")
      assert has_element?(view, "#farm-turn-6[aria-pressed=false]")
      assert has_element?(view, "#farm-duration", "#{2 * Moba.seconds_per_turn()}s")
      view |> element("#farm-start-button") |> render_click()

      started = Game.get_hero!(hero.id)
      assert started.pve_state == state
      assert started.pve_farming_turns == 2
      assert has_element?(view, "#farm-status", "In progress")
      refute has_element?(view, "#farm-start-button")
      refute has_element?(view, "[phx-hook=FarmClaimHotkey]")

      Game.update_hero!(started, %{
        pve_farming_started_at: Timex.shift(Timex.now(), seconds: -(2 * Moba.seconds_per_turn() + 1))
      })

      {:ok, ready_view, _} = live(conn, "/training")
      assert has_element?(ready_view, "#farm-status", "Ready to collect")
      assert has_element?(ready_view, "#farm-claim-button[phx-hook=FarmClaimHotkey][aria-keyshortcuts=Space] kbd", "SPACE")
      ready_view |> element("#farm-claim-button") |> render_click()

      claimed = Game.get_hero!(hero.id)
      assert claimed.pve_state == "alive"
      assert claimed.pve_current_turns == 4
      assert Map.fetch!(claimed, resource_field) > Map.fetch!(hero, resource_field)
      assert has_element?(ready_view, "#farm-history-table tbody tr")
      assert has_element?(ready_view, "#farm-turns-picker")
      refute has_element?(ready_view, "[phx-hook=FarmClaimHotkey]")
    end
  end

  test "one turn and no turns have usable farming states", %{conn: conn} do
    for turns <- [1, 0] do
      hero = create_base_hero(%{pve_tier: 4, pve_current_turns: turns, pve_total_turns: 15})
      Game.update_tutorial_step!(hero.player, 20)
      conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
      {:ok, view, _} = live(conn, "/training")

      if turns == 1 do
        view |> element("#farm-tab-mine") |> render_click()
        refute has_element?(view, "#farm-activity input[type=range]")
        assert has_element?(view, "#farm-turn-1[aria-pressed=true]")
        assert has_element?(view, "#farm-start-button", "Mine for 1 turn")
      else
        assert has_element?(view, "#training-ascent.is-challenge-stage")
        refute has_element?(view, "#farm-tab-battle, #farm-tab-meditation, #farm-tab-mine, #show-farm-tabs")
        refute has_element?(view, "#farm-activity")
        refute has_element?(view, "#farm-start-button")
        refute has_element?(view, "#farm-turns-picker")
      end
    end
  end

  test "farm-tab and live-duel switches retain their behavior", %{conn: conn} do
    hero = create_base_hero(%{pve_tier: 4})
    Game.update_tutorial_step!(hero.player, 20)
    conn = conn |> log_in_user(hero.player.user) |> put_session(:player_id, hero.player_id)
    {:ok, view, _} = live(conn, "/training")
    assert has_element?(view, "#show-farm-tabs[role=switch][checked]")

    view |> element("#show-farm-tabs") |> render_click(%{"value" => nil})
    refute Game.get_player!(hero.player_id).preferences.show_farm_tabs
    refute has_element?(view, "#farm-tab-mine")
    view |> element("#show-farm-tabs") |> render_click(%{"value" => "on"})
    assert Game.get_player!(hero.player_id).preferences.show_farm_tabs
    assert has_element?(view, "#farm-tab-mine")

    {:ok, arena, _} = live(conn, "/arena")
    assert has_element?(arena, "#set-status[role=switch]")
    arena |> element("#set-status") |> render_click(%{"value" => "on"})
    assert Game.get_player!(hero.player_id).status == "available"
    assert has_element?(arena, "#set-status[checked]")
    assert has_element?(arena, "#arena-live-pvp[data-available=true]", "Accepting live duel challenges")
    arena |> element("#set-status") |> render_click(%{})
    assert Game.get_player!(hero.player_id).status == "unavailable"
    refute has_element?(arena, "#set-status[checked]")
    assert has_element?(arena, "#arena-live-pvp[data-available=false]", "Go live to receive duel challenges")
  end
end
