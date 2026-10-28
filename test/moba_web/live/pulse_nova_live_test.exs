defmodule MobaWeb.PulseNovaLiveTest do
  use MobaWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Moba.Repo
  alias Moba.Game.Schema.Skill

  for prefix <- ["", "/v1"] do
    @prefix prefix

    test "#{prefix} Pulse Nova becomes a running indicator instead of a selectable skill", %{conn: conn} do
      key = "resources-#{Game.current_season().resource_uuid}"
      Cachex.del(:game_cache, key)
      on_exit(fn -> Cachex.del(:game_cache, key) end)

      nova =
        Repo.insert!(%Skill{
          code: "pulse_nova",
          name: "Pulse Nova",
          current: true,
          enabled: true,
          resource_uuid: Game.current_season().resource_uuid,
          level: 3,
          ultimate: true,
          base_damage: 80,
          mp_cost: 12,
          cooldown: 0,
          damage_type: "magic",
          image: base_skill().image,
          description: "Runs until there is not enough Energy for another pulse."
        })

      normal = base_skill()
      attacker = create_base_hero(%{total_hp: 5000, total_mp: 100})
      attacker = Game.update_hero!(attacker, %{skill_order: [nova.code, normal.code]}, nil, [nova, normal])
      defender = create_base_hero(%{total_hp: 5000, atk: 0, bot_difficulty: "test"})
      battle = create_basic_battle(attacker, defender)
      conn = init_test_session(conn, player_id: attacker.player_id)
      {:ok, view, _} = live(conn, "#{@prefix}/battles/#{battle.id}")
      assert has_element?(view, "#active-skill-#{nova.id}.can-use")

      render_click(view, "next-turn", %{"skill_id" => "#{nova.id}", "item_id" => "", "hero_id" => "#{attacker.id}"})

      assert has_element?(view, "#pulse-nova-running .pulse-nova-status", "ON · 12")
      assert has_element?(view, "#running-skill-#{nova.id}")
      refute has_element?(view, "#running-skill-#{nova.id}.can-use")
      refute has_element?(view, "#running-skill-#{nova.id}[phx-hook]")
      refute has_element?(view, "#pulse-nova-running .hotkey")
      refute has_element?(view, "#active-skill-#{nova.id}")
      assert has_element?(view, "#active-skill-#{normal.id} ~ .hotkey")
      assert has_element?(view, "#attack-button[data-skill='#{normal.id}']")
    end
  end
end
