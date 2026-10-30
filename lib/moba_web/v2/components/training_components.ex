defmodule MobaWeb.V2.Components.TrainingComponents do
  use Phoenix.Component

  import MobaWeb.Preview, only: [preview_path: 2]
  import MobaWeb.CoreComponents, only: [icon: 1, input: 1]
  import MobaWeb.V2.Components.GameComponents, only: [league_badge: 1]

  alias MobaWeb.V2.Components.GameHelpers, as: GH

  embed_templates "training_components/*"

  attr :current_hero, :map, required: true
  attr :current_player, :map, required: true
  attr :preview, :boolean, default: false
  attr :history, :boolean, default: false
  attr :show_controls, :boolean, default: true
  attr :battle_pending, :boolean, default: false

  def training_header(%{preview: true} = assigns) do
    hero = assigns.current_hero
    goal = max(hero.league_tier, max_available_league(hero))
    next = min(hero.league_tier + 1, goal)
    ready = hero.pve_current_turns == 0 && hero.league_tier < goal && hero.league_tier < Moba.master_league_tier()
    challenge_ready = ready && hero.pve_state == "alive" && !assigns.battle_pending

    assigns
    |> assign(:goal, goal)
    |> assign(:next, next)
    |> assign(:spent_turns, max(0, min(5, 5 - hero.pve_current_turns)))
    |> assign(:challenge_ready, challenge_ready)
    |> assign(:challenge_stage, challenge_ready && assigns.show_controls && !assigns.history)
    |> ascent()
  end

  def training_header(assigns), do: header(assigns)

  defp short_league(tier), do: String.replace(Moba.leagues()[tier], " League", "")

  defp ascent_status(hero, next, goal, pending) do
    cond do
      pending ->
        "Battle in progress"

      hero.pve_state == "dead" ->
        "Training interrupted"

      hero.pve_state in ["mining", "meditating"] ->
        "Training in progress"

      hero.league_tier >= goal ->
        "#{short_league(goal)} reached"

      hero.pve_current_turns == 0 && hero.boss_id != nil ->
        "Roshan awaits"

      hero.pve_current_turns == 0 ->
        "#{short_league(next)} challenge unlocked"

      true ->
        "Spend #{hero.pve_current_turns} #{if hero.pve_current_turns == 1, do: "turn", else: "turns"} to challenge #{short_league(next)}"
    end
  end

  defp elapsed_time(%{inserted_at: inserted_at}) do
    Timex.diff(Timex.now(), inserted_at, :minutes)
  end

  defp expert_hero?(%{pve_tier: tier}) when tier >= 4, do: true
  defp expert_hero?(_), do: false

  defp max_available_league(%{pve_tier: pve_tier, league_attempts: attempts} = hero) do
    max = Moba.max_available_league(pve_tier)

    if max != Moba.max_league_tier() || attempts == 0 || league_success_rate(hero) >= 100 do
      max
    else
      max - 1
    end
  end

  defp turn_percentage(%{pve_current_turns: turns}) do
    (5 - turns) * 100 / 5
  end

  defp league_success_rate(%{league_attempts: attempts, league_successes: successes}) when attempts > 0 do
    round(successes * 100 / attempts)
  end

  defp league_success_rate(_), do: 0
end
