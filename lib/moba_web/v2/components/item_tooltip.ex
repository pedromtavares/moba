defmodule MobaWeb.V2.Components.ItemTooltip do
  use Phoenix.Component
  import MobaWeb.CoreComponents, only: [icon: 1]
  import MobaWeb.V2.Components.SkillTooltip, only: [effect_rows: 1, metadata_rows: 1]

  alias Moba.Game.{ItemDescriptions, SkillDescriptions}
  alias MobaWeb.V2.Components.GameHelpers, as: GH

  @stats [
    {:base_hp, "Health", "health", "health"},
    {:base_mp, "Energy", "energy", "energy"},
    {:base_atk, "Attack", "attack", "attack"},
    {:base_power, "Power", "power", "power"},
    {:base_armor, "Armor", "armor", "armor"},
    {:base_speed, "Speed", "speed", "speed"}
  ]

  def render(item) do
    assigns = %{item: item, show_heading: true, __changed__: nil}
    assigns |> card() |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()
  end

  attr :item, :map, required: true
  attr :show_heading, :boolean, default: true

  def card(assigns) do
    item = assigns.item
    assigns = assign(assigns, content: ItemDescriptions.describe(item), stats: stats(item), metadata: metadata(item))

    ~H"""
    <article class="skill-tooltip item-tooltip" data-item-code={@item.code} data-rarity={@item.rarity}>
      <header :if={@show_heading} class="skill-tooltip-heading">
        <img :if={@item.image} src={GH.image_url(@item)} alt="" />
        <div>
          <h3>{@item.name}</h3>
          <span class="skill-tooltip-rank">
            <span class="item-tooltip-rarity">{String.capitalize(@item.rarity || "")}</span>
            <span>{if @item.active, do: "Active item", else: "Passive item"}</span>
          </span>
        </div>
      </header>
      <div class="item-tooltip-overview">
        <p :if={@content.summary} class="skill-tooltip-summary">{@content.summary}</p>
        <dl :if={@stats != []} class="item-tooltip-stats" aria-label="Equipment bonuses">
          <div
            :for={stat <- @stats}
            data-stat={stat.key}
            data-tone={stat.tone}
            class="skill-tooltip-effect item-tooltip-stat"
          >
            <dt><.icon name={"game-" <> stat.icon} class="skill-tooltip-effect-icon" /><span>{stat.label}</span></dt>
            <dd><strong>+{SkillDescriptions.number(stat.value)}</strong></dd>
          </div>
        </dl>
      </div>
      <div class="item-tooltip-effects">
        <.effect_rows effects={@content.effects} />
        <div :if={@content.notes != []} class="skill-tooltip-notes">
          <p :for={note <- @content.notes}>{note}</p>
        </div>
      </div>
      <.metadata_rows entries={@metadata} />
    </article>
    """
  end

  defp stats(item) do
    for {key, label, icon, tone} <- @stats, value = Map.get(item, key), is_number(value) && value > 0 do
      %{key: key, label: label, icon: icon, tone: tone, value: value}
    end
  end

  defp metadata(item) do
    cooldown = item.cooldown || 0

    Enum.reject(
      [
        if(item.active, do: %{kind: :energy, icon: "game-energy", label: "#{item.mp_cost || 0} Energy"}),
        if(item.active || cooldown > 0,
          do: %{
            kind: :cooldown,
            icon: "game-clock",
            label:
              if(cooldown == 0, do: "No cooldown", else: "#{cooldown} #{if cooldown == 1, do: "turn", else: "turns"}")
          }
        )
      ],
      &is_nil/1
    )
  end
end
