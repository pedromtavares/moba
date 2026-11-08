defmodule MobaWeb.V2.TrainingLive.Team do
  use MobaWeb, :v2_html
  import Phoenix.LiveView
  import MobaWeb.CoreComponents, only: [icon: 1]
  import MobaWeb.V2.Components.HeroBarComponents, only: [hero_bar: 1]
  alias Moba.Game.{TeamRuns, TeamTraining, TrainingEncounters}
  alias MobaWeb.V2.Components.TrainingComponents
  alias Phoenix.LiveView.JS

  embed_templates "team/*", suffix: "_template"
  def render(assigns), do: page_template(assigns)

  def init(socket),
    do:
      {:ok,
       assign(socket,
         run: nil,
         record: nil,
         initial_hero: nil,
         hero_ui: %{},
         show_shop: false,
         show_log: false,
         encounters: []
       )}

  def handle_params(params, _, socket) do
    record =
      if params["run"],
        do: TeamRuns.get!(socket.assigns.current_scope, params["run"]),
        else:
          TeamRuns.active(socket.assigns.current_scope, socket.assigns.current_player.id) ||
            TeamRuns.latest(socket.assigns.current_scope, socket.assigns.current_player.id)

    cond do
      record && record.phase == "abandoned" ->
        active = TeamRuns.active(socket.assigns.current_scope, record.player_id)
        path = if active, do: ~p"/training?#{[run: active.id]}", else: ~p"/new"
        {:noreply, push_navigate(socket, to: path)}

      record && record.phase != "draft" ->
        {:noreply, load(socket, record)}

      true ->
        {:noreply, push_navigate(socket, to: ~p"/new")}
    end
  end

  def handle_event(_, _, %{assigns: %{run: nil}} = socket), do: {:noreply, socket}

  # Selection is entirely local. Only an actual action supplies its hero to the server.
  def handle_event(event, %{"hero_id" => id} = params, socket) do
    id = integer(id)

    if Map.has_key?(socket.assigns.run.heroes, id) do
      socket = assign(socket, run: TeamTraining.select(socket.assigns.run, id), selected: socket.assigns.run.heroes[id])
      handle_event(event, Map.delete(params, "hero_id"), socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event("reward-mode", %{"mode" => mode}, socket) when mode in ["shared", "focus"],
    do: update_run(socket, &TeamTraining.reward_mode(&1, if(mode == "shared", do: :shared, else: :focus)))

  def handle_event("battle", %{"id" => id}, socket), do: begin_encounter(socket, &TeamTraining.battle(&1, integer(id)))
  def handle_event("league", _, socket), do: begin_encounter(socket, &TeamTraining.league/1)
  def handle_event("buyback", _, socket), do: update_run(socket, &TeamTraining.buyback/1)

  def handle_event("shard-buyback", _, socket) do
    socket
    |> apply_run_result(
      TeamRuns.shard_buyback(socket.assigns.current_scope, socket.assigns.record, socket.assigns.selected.id)
    )
  end

  def handle_event("restart", _, socket) do
    case TeamRuns.restart(socket.assigns.current_scope, socket.assigns.record) do
      {:ok, record} -> {:noreply, push_navigate(socket, to: ~p"/training?#{[run: record.id]}")}
      error -> apply_run_result(socket, error)
    end
  end

  def handle_event("skill", %{"code" => code}, socket), do: configure(socket, :skill, code)
  def handle_event("buy", %{"code" => code}, socket), do: configure(socket, :buy, code)
  def handle_event("sell", %{"code" => code}, socket), do: configure(socket, :sell, code)
  def handle_event("transmute", params, socket), do: configure(socket, :transmute, params)
  def handle_event("finish-transmute", params, socket), do: configure(socket, :transmute, params)
  def handle_event("auto-buy", _, socket), do: configure(socket, :auto_buy, !socket.assigns.selected.auto_buy)

  def handle_event("reorder-items", %{"codes" => codes}, socket), do: configure(socket, :inventory_order, codes)

  def handle_event("start-edit", _, socket), do: update_ui(socket, editing: true)
  def handle_event("cancel-edit", _, socket), do: update_ui(socket, editing: false)

  def handle_event("finalize-edit", params, socket) do
    {:noreply, socket} = update_ui(socket, editing: false)
    configure(socket, :orders, params)
  end

  def handle_event("show-shop", _, socket), do: update_ui(socket, show_shop: true, show_build: false)

  def handle_event("toggle-shop", _, socket) do
    update_ui(socket, show_shop: !socket.assigns.show_shop)
  end

  def handle_event("open-shop-item", %{"code" => code}, socket) do
    id = socket.assigns.selected.id
    prefix = if id == 1, do: "", else: "team-#{id}"

    {:noreply,
     MobaWeb.V2.Components.HeroBarComponents.open_shop_item(socket, socket.assigns.selected.hero, code, prefix)}
  end

  def handle_event("close-shop", _, socket), do: update_ui(socket, show_shop: false)
  def handle_event("hide-shop", _, socket), do: update_ui(socket, show_shop: false)
  def handle_event("show-build", _, socket), do: update_ui(socket, show_build: true)
  def handle_event("show-navigation", _, socket), do: update_ui(socket, show_build: false)
  def handle_event("hide-build", _, socket), do: update_ui(socket, show_build: false)
  def handle_event("show-log", _, socket), do: {:noreply, assign(socket, show_log: !socket.assigns.show_log)}
  def handle_event(_, _, socket), do: {:noreply, socket}
  def handle_info(:training_access_revoked, socket), do: {:noreply, redirect(socket, to: "/base")}
  def handle_info(_, socket), do: {:noreply, socket}

  defp begin_encounter(socket, fun) do
    {:noreply, socket} = update_run(socket, fun)

    if e = TeamTraining.active_encounter(socket.assigns.run),
      do: {:noreply, push_navigate(socket, to: TrainingEncounters.path(e, 1))},
      else: {:noreply, socket}
  end

  defp configure(socket, operation, value),
    do: update_run(socket, &TeamTraining.configure(socket.assigns.current_scope, &1, operation, value))

  defp update_run(socket, fun) do
    selected = socket.assigns.selected.id

    apply_run_result(
      socket,
      TeamRuns.update(socket.assigns.current_scope, socket.assigns.record, fn run ->
        run |> TeamTraining.select(selected) |> fun.()
      end)
    )
  end

  defp update_ui(socket, changes) do
    {show_shop, changes} = Keyword.pop(changes, :show_shop, socket.assigns.show_shop)
    id = socket.assigns.selected.id
    ui = Map.update(socket.assigns.hero_ui, id, Map.new(changes), &Map.merge(&1, Map.new(changes)))
    {:noreply, assign(socket, hero_ui: ui, show_shop: show_shop)}
  end

  defp apply_run_result(socket, result) do
    case result do
      {:ok, record} ->
        {:noreply, load(socket, record)}

      {:error, :stale} ->
        {:noreply,
         socket
         |> load(TeamRuns.get!(socket.assigns.current_scope, socket.assigns.record.id))
         |> put_flash(:info, "Your team changed in another tab. Its current state is loaded.")}

      {:error, :invalid_snapshot} ->
        {:noreply, unavailable(socket, socket.assigns.record)}

      {:error, :not_found} ->
        {:noreply, push_navigate(socket, to: ~p"/base")}

      _ ->
        {:noreply, socket}
    end
  end

  defp load(socket, record) do
    scope = socket.assigns.current_scope

    with {:ok, run} <- TeamRuns.read_state(record),
         {:ok, record} <- TeamRuns.restore_pending(scope, record, run) do
      load_run(socket, TeamRuns.finalize(scope, record), run)
    else
      {:error, :stale} -> push_navigate(socket, to: ~p"/training?#{[run: record.id]}")
      {:error, :invalid_snapshot} -> unavailable(socket, record)
      {:error, :not_found} -> push_navigate(socket, to: ~p"/base")
    end
  end

  defp unavailable(socket, record), do: assign(socket, run: nil, record: record, current_team: record)

  defp load_run(socket, record, saved_run) do
    incomplete =
      Enum.reject(saved_run.order, fn id ->
        match?([%{defender: %{}}, %{defender: %{}}, %{defender: %{}}], saved_run.targets[id])
      end)

    record =
      if saved_run.phase == :playing && saved_run.turns_left > 0 && incomplete != [] do
        case TeamRuns.update(socket.assigns.current_scope, record, &TeamTraining.refresh_targets(&1, incomplete)) do
          {:ok, refreshed} -> refreshed
          {:error, :stale} -> TeamRuns.get!(socket.assigns.current_scope, record.id)
          {:error, :invalid_snapshot} -> record
          {:error, :not_found} -> nil
        end
      else
        record
      end

    case record && TeamRuns.read_state(record) do
      {:ok, run} -> assign_run(socket, record, run)
      {:error, :invalid_snapshot} -> unavailable(socket, record)
      nil -> push_navigate(socket, to: ~p"/base")
    end
  end

  defp assign_run(socket, record, run) do
    player = Game.get_player!(record.player_id)
    encounters = TeamRuns.encounters(socket.assigns.current_scope, record.id)
    onboarding_guest = is_nil(player.user_id) && player.hero_collection == []

    socket =
      assign(socket,
        current_player: player,
        roshan: TeamTraining.boss_preview(run),
        onboarding_guest: onboarding_guest,
        battle_guide_hero: if(onboarding_guest, do: battle_guide_hero(run, encounters)),
        skill_guide_hero:
          if(run.phase == :playing && run.turns_left == 0 && TeamTraining.roster_alive?(run),
            do: List.first(TeamTraining.pending_skill_heroes(run))
          ),
        record: record,
        current_team: record,
        run: run,
        initial_hero: socket.assigns.initial_hero || run.selected,
        selected: run.heroes[run.selected],
        encounters: encounters
      )

    if run.phase == :finished, do: push_navigate(socket, to: ~p"/teams/#{record.id}"), else: socket
  end

  defp battle_guide_hero(%{phase: :playing, league_attempts: 0, turns_left: turns} = run, encounters) when turns > 0 do
    practiced =
      for %{kind: :farm, status: :finished, recipient: id} <- encounters, into: MapSet.new(), do: id

    Enum.find(run.order, fn id -> id not in practiced and not TeamTraining.dead?(run.heroes[id]) end)
  end

  defp battle_guide_hero(_, _), do: nil

  defp hero_panel(assigns) do
    run = %{assigns.run | selected: assigns.hero.id}
    player = assigns.current_player
    shards = player.user && player.user.shard_count

    guide_hero =
      if assigns.hero.hero.skill_levels_available > 0, do: assigns.hero, else: assigns.skill_guide_hero

    assigns
    |> assign(
      run: run,
      selected: assigns.hero,
      skill_guidance: if(assigns.skill_guide_hero, do: select_hero(guide_hero.id)),
      id_prefix: if(assigns.hero.id == 1, do: "", else: "team-#{assigns.hero.id}"),
      editing: Map.get(assigns.ui, :editing, false),
      show_build: Map.get(assigns.ui, :show_build, false),
      shard_buyback_count:
        if(TeamTraining.can_shard_buyback?(run) && shards && shards >= Moba.shard_buyback_price(shards), do: shards)
    )
    |> hero_panel_template()
  end

  defp select_hero(id) do
    JS.add_class("d-none", to: ".team-hero-panel")
    |> JS.remove_class("d-none", to: "#team-hero-panel-#{id}")
    |> JS.set_attribute({"aria-selected", "false"}, to: ".team-hero-selector [role=tab]")
    |> JS.set_attribute({"aria-pressed", "false"}, to: ".team-hero-selector [role=tab]")
    |> JS.set_attribute({"aria-selected", "true"}, to: "#team-select-#{id}")
    |> JS.set_attribute({"aria-pressed", "true"}, to: "#team-select-#{id}")
    |> JS.dispatch("team:hero-switched", to: "#team-training-page")
  end

  defp team_artwork(run) do
    run.targets
    |> Map.values()
    |> List.flatten()
    |> Enum.map(&GH.background_url(&1.defender.avatar))
    |> Enum.uniq()
  end

  defp integer(value) do
    case Integer.parse(to_string(value)) do
      {n, ""} -> n
      _ -> nil
    end
  end
end
