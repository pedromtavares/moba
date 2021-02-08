defmodule MobaWeb.BattleLiveView do
  use MobaWeb, :live_view

  alias MobaWeb.{BattleView, Tutorial}

  def mount(_, session, socket) do
    socket = assign_new(socket, :current_hero, fn -> Game.get_hero!(session["hero_id"]) end)
    current_hero = socket.assigns.current_hero

    {:ok,
     assign(socket,
       battle: nil,
       hero: nil,
       skill: nil,
       item: nil,
       turn: nil,
       last_turn: nil,
       action_turn_number: nil,
       show_shop: false,
       unreads: 0,
       tutorial_step: current_hero && current_hero.user.tutorial_step
     )}
  end

  def handle_params(%{"id" => id} = params, _uri, socket) do
    current_hero = socket.assigns.current_hero
    battle = Engine.get_battle!(id)
    current_hero && Engine.read_battle!(battle)

    snapshot =
      if current_hero && current_hero.id != battle.attacker_id && battle.type == "pvp" do
        battle.defender_snapshot
      else
        battle.attacker_snapshot
      end

    turn = Engine.next_battle_turn(battle)

    {:noreply,
     assign(socket,
       battle: battle,
       debug: Map.get(params, "debug"),
       hero: snapshot,
       turn: turn,
       last_turn: Engine.last_turn(battle),
       current_hero: current_hero,
       skill: BattleView.preselected_skill(turn.attacker, turn)
     )}
  end

  def handle_event("next-turn", %{"skill" => skill_id, "item" => item_id}, %{assigns: %{battle: battle}} = socket) do
    skill = skill_id != "" && Game.get_skill!(skill_id)
    item = item_id != "" && Game.get_item!(item_id)
    current_turn = Engine.last_turn(battle)
    battle = battle |> Engine.continue_battle!(%{skill: skill, item: item})

    last_turn = Engine.last_turn(battle)

    socket = check_tutorial(battle, socket)

    next_turn = Engine.next_battle_turn(battle)

    {:noreply,
     assign(socket,
       skill: BattleView.preselected_skill(next_turn.attacker, next_turn),
       item: nil,
       battle: battle,
       turn: next_turn,
       last_turn: last_turn,
       action_turn_number: (current_turn && current_turn.number + 1) || 1,
       hero: battle.attacker_snapshot
     )}
  end

  def handle_event("next-battle", %{"id" => id}, socket) do
    battle =
      socket.assigns.battle.attacker.id
      |> Engine.latest_battle()

    if battle.id != String.to_integer(id) && battle.type == "league" do
      {:noreply, socket |> push_patch(to: Routes.live_path(socket, MobaWeb.BattleLiveView, battle.id))}
    else
      {:noreply, socket |> push_redirect(to: Routes.live_path(socket, MobaWeb.JungleLiveView))}
    end
  end

  def render(assigns) do
    BattleView.render("show.html", assigns)
  end

  defp check_tutorial(battle, socket) do
    snapshot = battle.attacker_snapshot

    if battle.type == "league" && snapshot.league_step == 0 && battle.winner &&
         battle.winner.id == battle.attacker.id do
      Tutorial.next_step(socket, 11)
    else
      socket
    end
  end
end
