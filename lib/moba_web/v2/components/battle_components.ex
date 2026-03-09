defmodule MobaWeb.V2.Components.BattleComponents do
  use Phoenix.Component

  alias Moba.Game
  alias MobaWeb.V2.Components.GameHelpers, as: GH

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

  defp default_title(%Game.Schema.Item{} = item), do: GH.item_description(item)
  defp default_title(%Game.Schema.Skill{} = skill), do: GH.skill_description(skill)
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
end
