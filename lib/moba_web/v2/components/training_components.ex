defmodule MobaWeb.V2.Components.TrainingComponents do
  use Phoenix.Component

  import MobaWeb.Preview, only: [preview_path: 2]
  import MobaWeb.CoreComponents, only: [icon: 1, input: 1]
  import MobaWeb.V2.Components.GameComponents, only: [league_badge: 1, hero_skill_strip: 1]
  import MobaWeb.V2.Components.BattleComponents, only: [resource_segments: 3]

  alias MobaWeb.V2.Components.GameHelpers, as: GH

  embed_templates "training_components/*"

  attr :current_hero, :map, required: true
  attr :current_player, :map, required: true
  attr :preview, :boolean, default: false
  attr :history, :boolean, default: false
  attr :show_controls, :boolean, default: true
  attr :battle_pending, :boolean, default: false
  attr :target_battles_locked, :boolean, default: false
  attr :team_mode, :boolean, default: false
  attr :goal_override, :integer, default: nil
  attr :id_prefix, :string, default: ""
  attr :hero_id, :integer, default: nil
  attr :skill_guidance, Phoenix.LiveView.JS, default: nil
  attr :training_team, :map, default: nil
  slot :history_controls
  slot :reward_controls

  def training_header(%{preview: true} = assigns) do
    hero = assigns.current_hero

    farm_heroes =
      if assigns.training_team, do: Enum.map(assigns.training_team.heroes, fn {_, h} -> h.hero end), else: [hero]

    farm_size = length(farm_heroes)
    xp_farm = Enum.sum(Enum.map(farm_heroes, & &1.total_xp_farm))
    gold_farm = Enum.sum(Enum.map(farm_heroes, & &1.total_gold_farm))
    goal = assigns.goal_override || max(hero.league_tier, max_available_league(hero))
    next = min(hero.league_tier + 1, goal)
    ready = hero.pve_current_turns == 0 && hero.league_tier < goal && hero.league_tier < Moba.master_league_tier()
    challenge_ready = ready && hero.pve_state == "alive" && !assigns.battle_pending

    assigns
    |> assign(:farm_total, xp_farm + gold_farm)
    |> assign(:farm_size, farm_size)
    |> assign(
      :farm_breakdown,
      "#{farm_amount(xp_farm, farm_size)} XP farm · #{farm_amount(gold_farm, farm_size)} Gold farm"
    )
    |> assign(
      :perfect_run,
      if(assigns.training_team,
        do: Moba.Game.Training.PerfectRun.team?(assigns.training_team),
        else:
          Moba.Game.Training.PerfectRun.solo?(
            hero,
            assigns.battle_pending && hero.league_step == 0 && is_nil(hero.boss_id)
          )
      )
    )
    |> assign(:goal, goal)
    |> assign(:next, next)
    |> assign(:spent_turns, max(0, min(5, 5 - hero.pve_current_turns)))
    |> assign(:challenge_ready, challenge_ready)
    |> assign(:challenge_stage, challenge_ready && assigns.show_controls && !assigns.history)
    |> assign(
      :boss_ready,
      assigns.team_mode && hero.pve_current_turns == 0 && hero.league_tier == Moba.master_league_tier() &&
        hero.league_tier < goal
    )
    |> ascent()
  end

  def training_header(assigns), do: header(assigns)

  attr :id, :string, required: true
  attr :finished, :boolean, default: false

  def perfect_indicator(assigns) do
    ~H"""
    <span
      id={@id}
      class="farm-perfect"
      tabindex="0"
      data-toggle="tooltip"
      title={
        if @finished,
          do: "Perfect run: Grandmaster with 60K farm. Teams qualify with 60K average farm.",
          else: "This run is currently qualifying for Perfect: Grandmaster with 60K farm, or 60K average farm for teams."
      }
    >
      <.icon name="game-trophy" /> Perfect
    </span>
    """
  end

  attr :id, :string, required: true
  attr :total, :integer, required: true
  attr :cost, :integer, required: true
  attr :size, :integer, default: 1

  def buyback_farm_impact(assigns) do
    ~H"""
    <p id={@id} class="buyback-farm-impact">
      <span>{if @size == 3, do: "Avg Farm", else: "Total farm"} <strong>−{farm_amount(@cost, @size)}</strong></span>
      <span class="buyback-farm-change">
        {farm_amount(@total, @size)} <span aria-hidden="true">→</span> {farm_amount(@total - @cost, @size)}
      </span>
    </p>
    """
  end

  def team_farm(run), do: Enum.sum(Enum.map(run.heroes, fn {_, h} -> Moba.Game.Training.PerfectRun.farm(h.hero) end))

  defp farm_amount(value, size) do
    (value / size)
    |> :erlang.float_to_binary(decimals: 2)
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
  end

  attr :boss, :map, required: true
  attr :current_hp, :integer, default: nil
  attr :max_hp, :integer, default: nil
  attr :attempt, :integer, default: nil
  attr :id_prefix, :string, default: ""
  attr :hero_id, :integer, default: nil
  attr :skill_guidance, Phoenix.LiveView.JS, default: nil

  def boss_challenge(assigns) do
    assigns
    |> assign(
      :health,
      resource_segments(
        nil,
        assigns.current_hp || assigns.boss.total_hp,
        assigns.max_hp || assigns.boss.avatar.total_hp
      )
    )
    |> assign(:attempt, assigns.attempt || assigns.boss.league_attempts + 1)
    |> roshan()
  end

  attr :id, :string, required: true
  attr :action, Phoenix.LiveView.JS, required: true

  defp league_skill_warning(assigns) do
    ~H"""
    <button id={@id} type="button" class="league-skill-warning" phx-click={@action} aria-keyshortcuts="Space">
      <.icon name="game-xp" /> Spend all skill points to begin. <kbd aria-hidden="true">SPACE</kbd>
    </button>
    """
  end

  def target_rewards_tooltip(reward, label, difficulty, reward_mode \\ nil) do
    assigns = %{reward: reward, label: label, difficulty: difficulty, reward_mode: reward_mode}
    assigns |> rewards_tooltip() |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()
  end

  defp rewards_tooltip(assigns) do
    ~H"""
    <article class="rewards-tooltip" data-difficulty={@difficulty}>
      <header>
        <.icon name="game-swords" class="rewards-tooltip-emblem" />
        <div>
          <span class="rewards-tooltip-eyebrow">{if @reward_mode, do: "Total spoils", else: "Target rewards"}</span>
          <h3>{@label} target</h3>
        </div>
      </header>
      <dl>
        <div data-reward="xp">
          <dt><.icon name="game-xp" class="rewards-tooltip-icon" /><span>XP</span></dt>
          <dd>+{@reward}</dd>
        </div>
        <div data-reward="gold">
          <dt><.icon name="game-gold" class="rewards-tooltip-icon" /><span>Gold</span></dt>
          <dd>+{@reward}</dd>
        </div>
      </dl>
      <p :if={@reward_mode == :shared} data-reward-allocation="shared">
        Each hero: +{div(@reward, 3)} Gold and +{div(@reward, 3)} XP
      </p>
      <p :if={@reward_mode == :focus} data-reward-allocation="focus">
        Fighting hero: +{@reward} Gold and +{@reward} XP
      </p>
    </article>
    """
  end

  defp short_league(tier), do: String.replace(Moba.leagues()[tier], " League", "")

  defp ascent_status(assigns) do
    assigns = assign(assigns, :turns, assigns.hero.pve_current_turns)

    ~H"""
    <%= cond do %>
      <% @pending -> %>
        Battle in progress
      <% @boss_ready && @hero.pve_state == "alive" -> %>
        Roshan awaits
      <% @hero.pve_state == "dead" -> %>
        Training interrupted
      <% @hero.pve_state in ["mining", "meditating"] -> %>
        Training in progress
      <% @hero.league_tier >= @goal -> %>
        <span class="ascent-status-goal">{short_league(@goal)}</span> reached
      <% @turns == 0 && @hero.boss_id != nil -> %>
        Roshan awaits
      <% @turns == 0 -> %>
        <span class="ascent-status-league">{short_league(@next)}</span> challenge unlocked
      <% true -> %>
        {if @team_mode,
          do: "Battle #{@turns} #{if @turns == 1, do: "hero", else: "heroes"}",
          else: "Spend #{@turns} #{if @turns == 1, do: "turn", else: "turns"}"} to challenge
        <span class="ascent-status-league">{short_league(@next)}</span>
    <% end %>
    """
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
