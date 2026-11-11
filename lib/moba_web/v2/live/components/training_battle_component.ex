defmodule MobaWeb.V2.TrainingBattleComponent do
  @moduledoc "Persistent cinematic controls for team-training battles and matches."
  use MobaWeb, :v2_live_component
  import MobaWeb.CoreComponents, only: [icon: 1]
  alias Moba.Game.{TeamRuns, TeamTraining, TrainingEncounters}
  alias Moba.Game.Training.Loadouts
  alias Moba.Game.Training.Combat
  alias MobaWeb.V2.Components.CombatScene
  embed_templates "training_battle_component/*"

  def mount(socket),
    do:
      {:ok, assign(socket, auto_mode: :none, mode_token: 0, replay_turns: nil, view_index: nil, show_combat_log: false)}

  def update(assigns, socket) do
    {:ok, socket |> assign(assigns) |> load()}
  end

  def handle_event(_, _, %{assigns: %{unavailable: true}} = socket), do: {:noreply, socket}

  def handle_event(event, params, socket) do
    if scope = MobaWeb.V2.Hooks.TeamAccess.authorize(socket.assigns.access_session) do
      action(event, params, assign(socket, :current_scope, scope))
    else
      send(self(), :training_access_revoked)
      {:noreply, socket}
    end
  end

  defp action("toggle-combat-log", _, socket),
    do: {:noreply, assign(socket, show_combat_log: !socket.assigns.show_combat_log)}

  defp action("pause", _, socket),
    do: {:noreply, socket |> assign(auto_mode: :none, mode_token: socket.assigns.mode_token + 1) |> load()}

  defp action(mode, _, socket) when mode in ["auto-battle", "auto-match"] do
    auto = if mode == "auto-match", do: :match, else: :battle
    index = if !socket.assigns.live_group && auto == :match, do: 1, else: socket.assigns.index

    {:noreply,
     socket
     |> assign(
       auto_mode: auto,
       auto_index: index,
       view_index: index,
       replay_turns: if(socket.assigns.active || (socket.assigns.live_group && auto == :match), do: nil, else: 0),
       mode_token: socket.assigns.mode_token + 1
     )
     |> load()}
  end

  defp action("next-turn", params, %{assigns: %{active: true, can_act: true}} = socket) do
    turn = socket.assigns.turn
    hero = socket.assigns.hero
    skill = find_resource(hero.skills, params["skill_id"])
    item = find_resource(hero.items, params["item_id"])
    forced = turn.attacker.double_skill

    valid_skill =
      if forced,
        do: skill && skill.code == forced.code,
        else: params["skill_id"] in [nil, ""] || (skill && Engine.can_use_resource?(turn, skill))

    valid_item = params["item_id"] in [nil, ""] || (item && Engine.can_use_resource?(turn, item))

    if to_string(turn.attacker.hero_id) == params["hero_id"] && valid_skill && valid_item do
      {:noreply, mutate(socket, %{skill: skill, item: item, player_id: -1})}
    else
      {:noreply, load(socket)}
    end
  end

  defp action("training-playback-ready", %{"frame" => frame}, socket) do
    a = socket.assigns

    cond do
      frame != a.frame ->
        {:noreply, socket}

      a.active && (a.auto_mode != :none || (a.manual_view && a.turn.attacker.player_id != -1)) ->
        {:noreply, mutate(socket, %{auto: true})}

      a.transition ->
        {:noreply, socket |> assign(view_index: a.index + 1, replay_turns: nil) |> load()}

      !a.active && a.auto_mode != :none && a.full_battle.finished ->
        cond do
          a.shown_turns < length(a.full_battle.turns) ->
            {:noreply, socket |> assign(replay_turns: a.shown_turns + 1) |> load()}

          a.auto_mode == :match && a.index < length(a.replay.battles) && Enum.at(a.replay.battles, a.index).finished ->
            {:noreply, socket |> assign(view_index: a.index + 1, replay_turns: 0) |> load()}

          true ->
            {:noreply, socket |> assign(auto_mode: :none) |> load()}
        end

      true ->
        {:noreply, socket}
    end
  end

  defp action(_, _, socket), do: {:noreply, socket}

  defp mutate(socket, orders) do
    a = socket.assigns
    expected = {a.replay.id, a.index, length(a.full_battle.turns)}

    case TeamRuns.update(a.current_scope, a.team_record, fn run ->
           active = TeamTraining.active_encounter(run)
           current = if active, do: {active.id, length(active.battles), length(List.last(active.battles).turns)}
           if current == expected, do: TeamTraining.battle_action(a.current_scope, run, orders), else: run
         end) do
      {:ok, _} ->
        send(self(), {:training_updated, a.training_team_id})
        load(socket)

      {:error, reason} when reason in [:stale, :invalid_snapshot, :not_found] ->
        load(socket)
    end
  end

  defp load(socket) do
    a = socket.assigns

    with %{} = team <- TeamRuns.get(a.current_scope, a.training_team_id),
         {:ok, run} <- TeamRuns.read_state(team),
         %{} = record <- TeamRuns.get_encounter(a.current_scope, a.training_team_id, a.encounter_id),
         {:ok, replay} <- TrainingEncounters.replay(record),
         pending = TeamTraining.active_encounter(run),
         active_match = pending && pending[:id] == record.id,
         index = a.view_index || a.battle_index || if(active_match, do: length(replay.battles), else: 1),
         %{} = full <- Enum.at(replay.battles, index - 1),
         active = !!active_match && index == length(replay.battles) && !full.finished,
         true <- if(active, do: match?(%{duel: %{}}, run[:resolution]), else: full.turns != []) do
      socket
      |> assign(unavailable: false)
      |> load_battle(team, run, replay, pending, index, full, active, !!active_match)
    else
      _ -> assign(socket, unavailable: true)
    end
  end

  defp load_battle(socket, team_record, run, replay, pending, index, full, active, active_match) do
    a = socket.assigns

    mode =
      if a.auto_mode == :battle && (index != a[:auto_index] || (full.finished && is_nil(a.replay_turns))),
        do: :none,
        else: a.auto_mode

    # Auto all battles stops after the selected training match.
    mode = if !active_match && Map.get(replay, :status) == :finished && a.replay_turns == nil, do: :none, else: mode
    shown = if active || is_nil(a.replay_turns), do: length(full.turns), else: min(a.replay_turns, length(full.turns))

    battle =
      if shown == length(full.turns),
        do: full,
        else: %{
          full
          | turns: Enum.take(full.turns, shown),
            finished: false,
            winner: nil,
            winner_id: nil,
            winner_player_id: nil
        }

    duel = if active, do: run.resolution.duel
    prepared = if active, do: Combat.next_turn(duel), else: hd(full.turns)
    {battle, prepared} = display_battle(battle, prepared, team_record)
    first = List.first(battle.turns) || prepared
    initial = %{attacker: starting(first.attacker), defender: starting(first.defender)}
    manual_view = !is_nil(a.battle_index)
    scene_id = "training-#{replay.id}-#{index}"
    scene_battle = %{battle | id: scene_id}
    scene = CombatScene.build(scene_battle, initial, prepared, %{id: -1})
    status = if battle.finished && battle.winner_player_id == -1, do: "You Win", else: scene.status
    scene = %{scene | context: "Team training", status: status}
    frame = "#{scene_id}:#{shown}:#{a.mode_token}"

    transition =
      !!active_match && !!full.finished && index < length(replay.battles) && is_nil(a.replay_turns) &&
        (!manual_view || mode == :match)

    enabled = mode != :none || (active && manual_view) || transition

    scene =
      Map.merge(scene, %{turnDeadline: nil, fullReplay: true, trainingPlayback: %{enabled: enabled, frame: frame}})

    hero = Enum.find([battle.attacker, battle.defender], &(&1.id == prepared.attacker.hero_id))
    can_act = active && manual_view && prepared.attacker.player_id == -1 && mode == :none

    control_turn =
      if prepared.attacker.player_id == -1,
        do: prepared,
        else: %{prepared | attacker: prepared.defender, defender: prepared.attacker}

    control_hero = Enum.find([battle.attacker, battle.defender], &(&1.id == control_turn.attacker.hero_id))

    next_encounter = if pending && pending[:id] != replay.id && pending[:battle_ids] not in [nil, []], do: pending

    {continue_id, continue_path, continue_label} =
      cond do
        index < length(replay.battles) ->
          {"training-next-battle", battle_path(replay, index + 1), "Next battle"}

        next_encounter ->
          {"training-next-engagement", battle_path(next_encounter), "Next battle"}

        run.phase == :finished ->
          {"training-continue", ~p"/teams/#{team_record.id}", "View team"}

        true ->
          {"training-continue", home_path(a.training_team_id), "Continue training"}
      end

    assign(socket,
      continue_id: continue_id,
      continue_path: continue_path,
      continue_label: continue_label,
      earned_league:
        if(
          full.finished && index == length(replay.battles) &&
            Map.get(replay, :winner) == :radiant && replay.kind != :farm,
          do:
            if(replay.kind == :boss,
              do: 6,
              else: replay.league_tier + 1
            )
        ),
      engagement_complete: full.finished && index == length(replay.battles) && Map.get(replay, :status) == :finished,
      team_record: team_record,
      replay: replay,
      index: index,
      view_index: index,
      full_battle: full,
      battle: battle,
      active: active,
      live_group: active_match,
      transition: transition,
      auto_mode: mode,
      shown_turns: shown,
      turn: prepared,
      initial_turn: initial,
      combat_scene: scene,
      frame: frame,
      hero: hero,
      can_act: can_act,
      control_turn: control_turn,
      control_hero: control_hero,
      controls_disabled: !can_act,
      manual_view: manual_view,
      preview: true,
      debug: false,
      action_turn_number: nil,
      action_controls_id: "training-manual-turn-#{index}-#{prepared.number}",
      active_hero_id: if(can_act, do: prepared.attacker.hero_id),
      current_player: %{id: -1},
      event_target: a.myself,
      turn_timer: 0,
      skill: Engine.preselected_skill(control_turn),
      last_turn: List.last(battle.turns)
    )
  end

  defp display_battle(battle, prepared, team) do
    attacker = display_training_hero(battle.attacker, team)
    defender = display_training_hero(battle.defender, team)
    names = %{attacker.id => attacker.name, defender.id => defender.name}

    display_turn = fn turn ->
      %{attacker: attacker, defender: defender} = turn

      %{
        turn
        | attacker: %{attacker | name: Map.get(names, attacker.hero_id, attacker.name)},
          defender: %{defender | name: Map.get(names, defender.hero_id, defender.name)}
      }
    end

    battle = %{
      battle
      | attacker: attacker,
        defender: defender,
        initiator: display_training_hero(battle.initiator, team),
        winner: display_training_hero(battle.winner, team),
        turns: Enum.map(battle.turns, display_turn)
    }

    {battle, display_turn.(prepared)}
  end

  defp display_training_hero(%{name: _} = hero, team), do: %{hero | name: training_hero_name(hero, team)}
  defp display_training_hero(hero, _team), do: hero

  defp training_hero_name(%{player: %{id: -1}} = hero, team), do: TeamTraining.hero_name(hero, team)
  defp training_hero_name(hero, _team), do: hero.name

  defp find_resource(resources, id), do: Enum.find(resources, &(to_string(&1.id) == id))

  defp opponent_steps(replay, battle, index) do
    health =
      (Enum.take(replay.battles, index - 1) ++ [battle])
      |> Enum.reduce(%{}, fn shown, health ->
        case List.last(shown.turns) do
          nil -> health
          turn -> Enum.reduce([turn.attacker, turn.defender], health, &Map.put(&2, &1.hero_id, &1.current_hp))
        end
      end)

    next = Enum.find(replay.dire, &(Map.get(health, &1.id, &1.hp) > 0))
    ongoing = replay.status != :finished || index < length(replay.battles)

    Enum.map(replay.dire, fn unit ->
      state =
        cond do
          Map.get(health, unit.id, unit.hp) <= 0 -> "defeated"
          ongoing && next && unit.id == next.id -> "next"
          true -> "pending"
        end

      %{
        id: unit.id,
        hero: unit.hero,
        state: state,
        label:
          if(state == "pending" && !ongoing,
            do: "Survived",
            else: %{"defeated" => "Defeated", "next" => "Up next", "pending" => "Waiting"}[state]
          )
      }
    end)
  end

  defp home_path(id), do: ~p"/training?#{[run: id]}"
  defp battle_path(encounter, index \\ nil), do: Game.TrainingEncounters.path(encounter, index)
  defp starting(h), do: %{h | current_hp: h.starting_hp || h.total_hp, current_mp: h.starting_mp || h.total_mp}

  def render(%{unavailable: true} = assigns) do
    ~H"""
    <div>
      <.hud_notice id="training-replay-unavailable" title="This training battle could not be loaded.">
        <:actions>
          <.link navigate={home_path(@training_team_id)} class="btn btn-secondary">Back to training</.link>
        </:actions>
      </.hud_notice>
    </div>
    """
  end

  def render(assigns), do: encounter(assigns)
end
