defmodule MobaWeb.V2.Components.BattleComponents do
  use Phoenix.Component

  alias Moba.Game
  alias MobaWeb.V2.Components.GameHelpers, as: GH

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
end
