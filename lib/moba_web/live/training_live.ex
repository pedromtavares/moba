defmodule MobaWeb.TrainingLive do
  use MobaWeb, :live_view

  alias MobaWeb.{TutorialComponent, Shop, TrainingView}

  def mount(_, _, socket) do
    with %{assigns: %{current_hero: hero}} = socket = socket_init(socket) do
      if hero && connected?(socket) do
        Game.subscribe_to_hero(hero.id)
        TutorialComponent.subscribe(hero.user_id)
      end

      {:ok, socket}
    end
  end

  def handle_params(_params, _uri, %{assigns: %{current_hero: hero}} = socket) do
    socket = if hero.gold >= 400 && length(hero.items) > 0, do: TutorialComponent.next_step(socket, 6), else: socket

    {:noreply, socket}
  end

  def handle_event("battle", %{"id" => id}, socket) do
    with socket = TutorialComponent.next_step(socket, 2),
         battle = Game.get_target!(id) |> Engine.create_pve_battle!() do
      {:noreply, push_redirect(socket, to: Routes.live_path(socket, MobaWeb.BattleLive, battle.id))}
    end
  end

  def handle_event("refresh-targets", _, %{assigns: %{current_hero: hero}} = socket) do
    with hero = Game.refresh_targets!(hero),
         targets = Game.list_targets(hero) do
      {:noreply, assign(socket, current_hero: hero, targets: targets)}
    end
  end

  def handle_event("league", _, %{assigns: %{current_hero: hero}} = socket) do
    with socket = TutorialComponent.next_step(socket, 10),
         battle = Game.prepare_league_challenge!(hero) |> Engine.create_league_battle!() do
      {:noreply, socket |> push_redirect(to: Routes.live_path(socket, MobaWeb.BattleLive, battle.id))}
    end
  end

  def handle_event("buyback", _, %{assigns: %{current_hero: hero}} = socket) do
    with hero = Game.buyback!(hero) do
      Game.broadcast_to_hero(hero.id)
      {:noreply, assign(socket, current_hero: hero)}
    end
  end

  def handle_event("shard-buyback", _, %{assigns: %{current_hero: hero}} = socket) do
    with hero = Game.shard_buyback!(hero) do
      Game.broadcast_to_hero(hero.id)
      {:noreply, assign(socket, current_hero: hero)}
    end
  end

  def handle_event("restart", _, %{assigns: %{current_hero: hero, current_user: user}} = socket) do
    with _ <- Game.archive_hero!(hero),
         skills = Enum.map(hero.skills, &Game.get_skill_by_code!(&1.code, true, 1)) do
      Moba.create_current_pve_hero!(%{name: hero.name}, user, hero.avatar, skills)

      {:noreply, socket |> redirect(to: "/training")}
    end
  end

  def handle_event("show-farm-tabs", params, %{assigns: %{current_user: user}} = socket) do
    with show_farm_tabs = not is_nil(Map.get(params, "value")),
         user = Accounts.update_preferences!(user, %{show_farm_tabs: show_farm_tabs}) do
      {:noreply, assign(socket, current_user: user)}
    end
  end

  def handle_event("show-meditation", _, %{assigns: %{current_hero: hero}} = socket) do
    time_trigger()
    {:noreply, assign(socket, farm_tab: "meditation", farm_rewards: farm_rewards_for(hero, "meditating"))}
  end

  def handle_event("show-mine", _, %{assigns: %{current_hero: hero}} = socket) do
    time_trigger()
    {:noreply, assign(socket, farm_tab: "mine", farm_rewards: farm_rewards_for(hero, "mining"))}
  end

  def handle_event("show-gank", _, socket) do
    {:noreply, assign(socket, farm_tab: "gank")}
  end

  def handle_event("tutorial3", _, socket) do
    {:noreply, socket |> TutorialComponent.next_step(3) |> Shop.open()}
  end

  def handle_event("tutorial5", _, socket) do
    {:noreply, socket |> TutorialComponent.next_step(5)}
  end

  def handle_event("finish-tutorial", _, socket) do
    {:noreply, TutorialComponent.finish_training(socket)}
  end

  def handle_event("select-turns", params, %{assigns: %{current_hero: hero}} = socket) do
    with turns = String.to_integer(params["turns"]),
         selected_turns = if(turns > hero.pve_current_turns, do: hero.pve_current_turns, else: turns) do
      {:noreply, assign(socket, selected_turns: selected_turns)}
    end
  end

  def handle_event(
        "start-farming",
        %{"state" => state},
        %{assigns: %{current_hero: hero, selected_turns: turns}} = socket
      )
      when state in ["meditating", "mining"] do
    with updated_hero = Game.start_farming!(hero, state, turns) do
      time_trigger()
      {:noreply, assign(socket, current_hero: updated_hero)}
    end
  end

  def handle_event("finish-farming", _, %{assigns: %{current_hero: %{id: id, pve_state: state} = hero}} = socket) do
    with %{pve_current_turns: selected_turns} = updated_hero = Game.finish_farming!(hero),
         farm_rewards = farm_rewards_for(updated_hero, state),
         targets = Game.list_targets(updated_hero) do
      Game.broadcast_to_hero(id)

      {:noreply,
       assign(socket,
         current_hero: updated_hero,
         farm_rewards: farm_rewards,
         selected_turns: selected_turns,
         targets: targets
       )}
    end
  end

  def handle_info({:tutorial, %{step: step}}, socket) do
    {:noreply, assign(socket, tutorial_step: step)}
  end

  def handle_info({"hero", %{id: id}}, socket) do
    {:noreply, assign(socket, current_hero: Game.get_hero!(id))}
  end

  def handle_info(:current_time, %{assigns: %{current_hero: hero}} = socket) do
    if TrainingView.farming_progression(hero, %{current_time: Timex.now()}) < 100 do
      Process.send_after(self(), :current_time, 1000)
    end

    {:noreply, assign(socket, current_time: Timex.now())}
  end

  def handle_info(:current_time, socket), do: {:noreply, socket}

  def render(assigns) do
    MobaWeb.TrainingView.render("index.html", assigns)
  end

  defp current_farm_tab(%{pve_state: "meditating"}), do: "meditation"
  defp current_farm_tab(%{pve_state: "mining"}), do: "mine"
  defp current_farm_tab(_), do: "gank"

  defp farm_rewards_for(hero, state),
    do: Enum.filter(hero.pve_farming_rewards, &(&1.state == state)) |> Enum.sort_by(& &1.started_at, {:desc, DateTime})

  defp list_targets(hero) do
    targets = Game.list_targets(hero)
    if length(targets) > 0, do: targets, else: Game.generate_targets!(hero) |> Game.list_targets()
  end

  defp maybe_redirect(%{assigns: %{current_hero: %{finished_at: finished_at} = hero}} = socket)
       when not is_nil(finished_at) do
    redirect(socket, to: Routes.live_path(socket, MobaWeb.HeroLive, hero.id))
  end

  defp maybe_redirect(%{assigns: %{current_hero: current_hero}} = socket) when is_nil(current_hero) do
    redirect(socket, to: "/base")
  end

  defp maybe_redirect(socket), do: socket

  defp socket_init(%{assigns: %{current_hero: hero}} = socket) do
    with updated_hero = Game.maybe_finish_pve(hero) do
      socket
      |> assign(current_hero: updated_hero)
      |> maybe_redirect()
      |> training_assigns()
    end
  end

  defp training_assigns(%{assigns: %{current_hero: hero}} = socket) when not is_nil(hero) do
    Cachex.del(:game_cache, hero.user_id)

    with current_time = Timex.now(),
         farm_rewards = farm_rewards_for(hero, "meditating"),
         farm_tab = current_farm_tab(hero),
         pending_battle = Engine.pending_battle(hero.id),
         targets = list_targets(hero) do
      if Enum.member?(["meditation", "mine"], farm_tab), do: time_trigger()

      assign(socket,
        current_hero: hero,
        current_time: current_time,
        pending_battle: pending_battle,
        farm_rewards: farm_rewards,
        farm_tab: farm_tab,
        farm_rewards: [],
        selected_turns: hero.pve_current_turns,
        sidebar_code: "training",
        targets: targets,
        tutorial_step: hero.user.tutorial_step
      )
    end
  end

  defp training_assigns(socket), do: socket

  defp time_trigger, do: Process.send_after(self(), :current_time, 100)
end
