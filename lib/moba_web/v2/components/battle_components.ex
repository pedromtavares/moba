defmodule MobaWeb.V2.Components.BattleComponents do
  use Phoenix.Component
  import Moba.Utils, only: [username: 1]

  alias Moba.Game
  alias MobaWeb.V2.Components.GameHelpers, as: GH
  alias MobaWeb.V2.Components.TooltipComponents, as: TT

  @effect_pattern ~r/\[(armor|damage|power|hp|mp|status|speed)\](.+?)\[\/\1\]/

  attr :resource, :map, required: true
  attr :title, :string, default: nil
  attr :id, :string, default: nil
  attr :class, :string, required: true
  attr :rest, :global,
    include: ~w(
      phx-click
      phx-value-id
      phx-hook
      data-index
      data-name
      data-resource
    )

  def battle_resource_image(assigns) do
    ~H"""
    <img
      src={GH.image_url(@resource)}
      data-toggle="tooltip"
      title={@title || default_title(@resource)}
      class={@class}
      id={@id}
      alt={@resource.name}
      {@rest}
    />
    """
  end

  attr :class, :string, default: "item-img empty-item"

  def empty_item_slot(assigns) do
    ~H"""
    <div class={@class}></div>
    """
  end

  attr :resource, :map, required: true
  attr :battler, :map, required: true

  def resource_status_badge(assigns) do
    ~H"""
    <%= cond do %>
      <% insufficient_mp?(@resource, @battler) -> %>
        <span class="badge badge-pill badge-primary cooldown">
          <i class="fa fa-bolt"></i> {@resource.mp_cost}
        </span>
      <% cooldown = resource_cooldown(@resource, @battler) -> %>
        <span class="badge badge-pill badge-warning cooldown">
          <i class="fa fa-clock"></i> {cooldown}
        </span>
      <% true -> %>
        <span class="badge badge-pill badge-danger passive">
          <i class="fa fa-times"></i>
        </span>
      <% end %>
    """
  end

  attr :code, :string, required: true
  attr :title, :string, required: true
  attr :class, :string, required: true

  def battle_status_icon(assigns) do
    ~H"""
    <img
      src={"/images/#{@code}.png"}
      data-toggle="tooltip"
      title={@title}
      class={@class}
      alt={@code}
    />
    """
  end

  attr :effect, :string, required: true
  attr :class, :string, default: nil

  def effect_text(assigns) do
    assigns = assign(assigns, :lines, effect_lines(assigns.effect))

    ~H"""
    <span class={@class}>
      <%= for {line, index} <- Enum.with_index(@lines) do %>
        <%= for fragment <- line do %>
          <%= if fragment.class do %>
            <span class={fragment.class}>{fragment.text}</span>
          <% else %>
            {fragment.text}
          <% end %>
        <% end %>
        <%= if index < length(@lines) - 1 do %>
          <br />
        <% end %>
      <% end %>
    </span>
    """
  end

  attr :title, :string, required: true
  attr :class, :string, default: "col-12 col-md-8 center victory-title margin-auto"
  slot :inner_block

  def battle_result_header(assigns) do
    ~H"""
    <div class="row">
      <div class={@class}>
        <h3>
          {@title}
          <%= if @inner_block != [] do %>
            <br />
            <small><%= render_slot(@inner_block) %></small>
          <% end %>
        </h3>
      </div>
    </div>
    """
  end

  attr :battle, :map, required: true

  def pve_reward_badges(assigns) do
    ~H"""
    <%= if @battle.rewards.total_xp > 0 do %>
      <span class="badge badge-pill badge-light-primary">+{@battle.rewards.total_xp} XP</span>
    <% end %>
    <%= if @battle.rewards.total_gold > 0 do %>
      <span class="badge badge-pill badge-light-warning">+{@battle.rewards.total_gold}g</span>
    <% end %>
    <%= if @battle.rewards.total_xp == 0 do %>
      <span class="badge badge-pill badge-light-dark">No rewards given on defeat</span>
    <% end %>
    """
  end

  attr :duel, :map, required: true

  def duel_reward_badges(assigns) do
    ~H"""
    <%= if @duel.rewards do %>
      <%= if @duel.rewards.attacker_pvp_points != 0 do %>
        <span class={duel_reward_badge_class(@duel.rewards.attacker_pvp_points)}>
          {username(@duel.player)}: {duel_reward_points_label(@duel.rewards.attacker_pvp_points)}
        </span>
      <% end %>
      <%= if @duel.rewards.defender_pvp_points != 0 do %>
        <span class={duel_reward_badge_class(@duel.rewards.defender_pvp_points)}>
          {username(@duel.opponent_player)}: {duel_reward_points_label(@duel.rewards.defender_pvp_points)}
        </span>
      <% end %>
    <% end %>
    """
  end

  slot :inner_block, required: true
  attr :class, :string, default: "row battle-border-top pt-1 mt-1"

  def battle_action_row(assigns) do
    ~H"""
    <div class={@class}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  attr :navigate, :string, required: true
  attr :id, :string, required: true
  attr :class, :string, required: true
  attr :label, :string, required: true
  attr :icon, :string, default: nil

  def battle_nav_action(assigns) do
    ~H"""
    <.link navigate={@navigate} class={@class} phx-hook="Loading" id={@id}>
      <span class="loading-text">
        <i :if={@icon} class={@icon}></i>
        {@label}
      </span>
    </.link>
    """
  end

  attr :id, :string, required: true
  attr :class, :string, required: true
  attr :label, :string, required: true
  attr :icon, :string, default: nil
  attr :click, :string, required: true
  attr :value_id, :any, default: nil

  def battle_event_action(assigns) do
    ~H"""
    <a
      href="javascript:;"
      id={@id}
      phx-click={@click}
      phx-value-id={@value_id}
      class={@class}
      phx-hook="Loading"
    >
      <span class="loading-text">
        <i :if={@icon} class={@icon}></i>
        {@label}
      </span>
    </a>
    """
  end

  attr :class, :string, required: true
  attr :label, :string, required: true
  attr :icon, :string, required: true

  def battle_guest_create_action(assigns) do
    ~H"""
    <a href="/start" class={@class}><i class={@icon}></i> {@label}</a>
    """
  end

  attr :hero, :map, required: true
  attr :step, :integer, required: true
  attr :label, :string, required: true
  attr :variant, :string, values: ~w(winner loser), required: true

  def league_step(assigns) do
    ~H"""
    <%= if show_league_step?(@hero, @step) do %>
      <li class="nav-item">
        <a href="javascript:;" class={league_step_class(@hero, @step, @variant)}>
          <span class="number">
            <%= if league_step_icon(@hero, @step, @variant) == :check do %>
              <i class="fa fa-check"></i>
            <% else %>
              <%= if league_step_icon(@hero, @step, @variant) == :times do %>
                <i class="fa fa-times"></i>
              <% else %>
                {@step}
              <% end %>
            <% end %>
          </span>
          <span class="d-none d-md-inline">{@label}</span>
        </a>
      </li>
    <% end %>
    """
  end

  attr :battle, :map, required: true

  def battle_over_action(assigns) do
    ~H"""
    <div class="row">
      <div class="text-center col-12">
        <%= case @battle.type do %>
          <% "pve" -> %>
            <.battle_nav_action
              navigate="/training"
              class="btn btn-danger width-lg text-white"
              id="battle-over-training"
              icon=""
              label="Battle Over!"
            />
          <% "league" -> %>
            <.battle_event_action
              id="league-battle-over"
              click="next-battle"
              value_id={@battle.id}
              class="btn btn-danger width-lg text-white"
              icon=""
              label="Battle Over!"
            />
          <% "duel" -> %>
            <.battle_nav_action
              navigate={"/arena/#{@battle.duel_id}"}
              class="btn btn-danger width-lg text-white"
              id="battle-over-duel"
              icon=""
              label="Battle Over!"
            />
          <% _ -> %>
            <span></span>
        <% end %>
      </div>
    </div>
    """
  end

  attr :battle, :map, required: true

  def share_battle_action(assigns) do
    ~H"""
    <div class="row mt-5">
      <div class="text-center col-12">
        <button
          class="btn btn-primary width-lg text-white"
          data-link={"https://browsermoba.com/battles/#{@battle.id}"}
          phx-hook="ShareBattle"
          id="share-battle"
        >
          Share this Battle
        </button>
      </div>
    </div>
    """
  end

  defp default_title(%Game.Schema.Item{} = item), do: TT.item_tooltip(item)
  defp default_title(%Game.Schema.Skill{} = skill), do: TT.skill_tooltip(skill)
  defp default_title(resource), do: resource.name

  defp insufficient_mp?(resource, battler) do
    resource.mp_cost && battler.current_mp < resource.mp_cost
  end

  defp resource_cooldown(%Game.Schema.Item{active: false}, _), do: nil
  defp resource_cooldown(%Game.Schema.Skill{passive: true}, _), do: nil

  defp resource_cooldown(resource, battler) do
    cooldown = battler.cooldowns[resource.code]
    display_cooldown(cooldown && cooldown + 1)
  end

  defp display_cooldown(result) when result < 0, do: 0
  defp display_cooldown(result), do: result

  defp effect_lines(effect) do
    effect
    |> to_string()
    |> String.split("\n")
    |> Enum.map(&effect_fragments/1)
  end

  defp effect_fragments(""), do: [%{class: nil, text: ""}]

  defp effect_fragments(text) do
    case Regex.run(@effect_pattern, text, return: :index) do
      [{start, length}, {tag_start, tag_length}, {content_start, content_length}] ->
        prefix = binary_part(text, 0, start)
        tag = binary_part(text, tag_start, tag_length)
        content = binary_part(text, content_start, content_length)
        suffix_start = start + length
        suffix = binary_part(text, suffix_start, byte_size(text) - suffix_start)

        prefix_fragment(prefix) ++
          [%{class: effect_class(tag), text: content}] ++
          effect_fragments(suffix)

      nil ->
        [%{class: nil, text: text}]
    end
  end

  defp prefix_fragment(""), do: []
  defp prefix_fragment(text), do: [%{class: nil, text: text}]

  defp effect_class("armor"), do: "text-warning"
  defp effect_class("damage"), do: "text-danger"
  defp effect_class("power"), do: "text-pink"
  defp effect_class("hp"), do: "text-success"
  defp effect_class("mp"), do: "text-primary"
  defp effect_class("status"), do: "text-dark"
  defp effect_class("speed"), do: "text-purple"

  defp duel_reward_badge_class(points) when points > 0, do: "badge badge-pill badge-light-success"
  defp duel_reward_badge_class(_points), do: "badge badge-pill badge-light-dark"

  defp duel_reward_points_label(points) when points > 0, do: "+#{points} Season Points"
  defp duel_reward_points_label(points), do: "#{points} Season Points"

  defp show_league_step?(hero, step), do: step <= Game.max_league_step_for(hero.league_tier)

  defp league_step_class(hero, step, "winner"),
    do: "nav-link #{if hero.league_step > step, do: "success"}"

  defp league_step_class(hero, step, "loser") do
    "nav-link #{if hero.previous_league_step == step, do: "failure"} #{if hero.previous_league_step > step, do: "success"}"
  end

  defp league_step_icon(hero, step, "winner") do
    if hero.league_step > step, do: :check, else: :step
  end

  defp league_step_icon(hero, step, "loser") do
    cond do
      hero.previous_league_step == step -> :times
      hero.previous_league_step > step -> :check
      true -> :step
    end
  end
end
