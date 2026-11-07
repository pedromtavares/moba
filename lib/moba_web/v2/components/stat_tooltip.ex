defmodule MobaWeb.V2.Components.StatTooltip do
  use Phoenix.Component

  import MobaWeb.CoreComponents, only: [icon: 1]

  alias Moba.Game.SkillDescriptions

  @stats %{
    hp: {"Health", "health", "damage", :total_hp, :item_hp, :hp_per_level},
    mp: {"Energy", "energy", "energy", :total_mp, :item_mp, :mp_per_level},
    atk: {"Attack", "attack", "attack", :atk, :item_atk, :atk_per_level},
    power: {"Power", "power", "power", :power, :item_power, nil},
    armor: {"Armor", "armor", "armor", :armor, :item_armor, nil},
    speed: {"Speed", "speed", "speed", :speed, :item_speed, nil}
  }

  def title(hero, stat, "detailed") do
    {name, icon, tone, base_key, items_key, growth_key} = Map.fetch!(@stats, stat)
    base = Map.fetch!(hero, base_key)
    items = Map.fetch!(hero, items_key)

    %{
      name: name,
      icon: "game-" <> icon,
      tone: tone,
      summary: summary(stat),
      base: base,
      items: items,
      growth: growth_key && Map.get(hero.avatar, growth_key)
    }
    |> card()
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  def title(_hero, stat, _mode), do: @stats |> Map.fetch!(stat) |> elem(0)

  defp card(assigns) do
    ~H"""
    <article class="skill-tooltip stat-tooltip" data-tone={@tone}>
      <header class="skill-tooltip-heading">
        <span class="stat-tooltip-emblem"><.icon name={@icon} /></span>
        <h3>{@name}</h3>
        <strong class="stat-tooltip-total">
          <span class="sr-only">Total </span>{SkillDescriptions.number(@base + @items)}
        </strong>
      </header>
      <p :for={paragraph <- @summary} class="skill-tooltip-summary">{paragraph}</p>
      <dl class="skill-tooltip-effects">
        <div class="skill-tooltip-effect" data-stat-source="base">
          <dt><.icon name={@icon} class="skill-tooltip-effect-icon" /><span>Base</span></dt>
          <dd><strong>{SkillDescriptions.number(@base)}</strong></dd>
        </div>
        <div class="skill-tooltip-effect" data-stat-source="items">
          <dt><.icon name="game-item" class="skill-tooltip-effect-icon" /><span>From items</span></dt>
          <dd><strong>{bonus(@items)}</strong></dd>
        </div>
        <div :if={is_number(@growth)} class="skill-tooltip-effect" data-stat-source="growth">
          <dt><.icon name="game-rank-up" class="skill-tooltip-effect-icon" /><span>Per level</span></dt>
          <dd><strong>{bonus(@growth)}</strong></dd>
        </div>
      </dl>
    </article>
    """
  end

  defp bonus(value) when value > 0, do: "+" <> SkillDescriptions.number(value)
  defp bonus(value), do: SkillDescriptions.number(value)

  defp summary(:hp), do: ["At 0 Health, you fall in battle and earn no rewards."]

  defp summary(:mp) do
    [
      "Skills and active items spend Energy. At 0 Energy, use Basic Attacks to deal 100% of Attack as Normal Damage."
    ]
  end

  defp summary(:atk), do: ["Determines the damage of Basic Attacks and scales many skills and items."]
  defp summary(:power), do: ["Each point increases damage and regeneration by 1%."]

  defp summary(:armor) do
    ["Each point reduces damage on defending turns by 1%, up to 90%. It applies after the attacker’s Power bonus."]
  end

  defp summary(:speed) do
    [
      "Each point gives a 1% chance to act first.",
      "When defending, each point above 100 adds a 1% chance to Evade an eligible Normal Damage hit. Evade costs no Energy and has a 2-turn cooldown."
    ]
  end
end
