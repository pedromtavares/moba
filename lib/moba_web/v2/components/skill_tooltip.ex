defmodule MobaWeb.V2.Components.SkillTooltip do
  use Phoenix.Component
  import MobaWeb.CoreComponents, only: [icon: 1]

  alias Moba.Game.SkillDescriptions, as: Copy
  alias MobaWeb.V2.Components.GameHelpers, as: GH

  def render(skill, opts \\ []) do
    assigns = %{
      skill: skill,
      content: Copy.describe(skill),
      full: Keyword.get(opts, :full, true),
      show_name: Keyword.get(opts, :show_name, true),
      details_only: Keyword.get(opts, :details_only, false),
      upgrade: Keyword.get(opts, :next) |> upgrade_for(skill)
    }

    assigns |> card() |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()
  end

  defp card(assigns) do
    ~H"""
    <article class="skill-tooltip" data-skill-code={@skill.code}>
      <header :if={!@details_only} class="skill-tooltip-heading">
        <img :if={@show_name && Map.get(@skill, :image)} src={GH.image_url(@skill)} alt="" />
        <div>
          <h3 :if={@show_name}>{@skill.name}</h3>
          <span class="skill-tooltip-rank">
            <span :if={Map.get(@skill, :level)}>Rank {@skill.level}</span>
            <span :if={Map.get(@skill, :ultimate)}>Ultimate</span>
            <span :if={Map.get(@skill, :passive)}>Passive</span>
          </span>
        </div>
      </header>
      <p :if={!@details_only} class="skill-tooltip-summary">{@content.summary}</p>
      <%= if @full do %>
        <.effect_rows effects={@content.effects} />
        <div :if={@content.notes != []} class="skill-tooltip-notes">
          <p :for={note <- @content.notes}>{note}</p>
        </div>
        <.metadata_rows entries={metadata(@skill)} />
        <section :if={@upgrade} class="skill-upgrade-preview" aria-label="Next skill rank">
          <header><span>Next rank</span><strong>Rank {@upgrade.rank}</strong></header>
          <dl class="skill-tooltip-changes">
            <div
              :for={change <- @upgrade.changes}
              class="skill-tooltip-change"
              data-change={change.key}
              data-tone={change.tone}
            >
              <dt><.icon name={effect_icon(change)} class="skill-tooltip-effect-icon" /><span>{change.label}</span></dt>
              <dd>
                <span class="skill-tooltip-before">{change.before}</span><span
                  class="skill-tooltip-arrow"
                  aria-hidden="true"
                >→</span><strong>{change.after}</strong>
              </dd>
            </div>
          </dl>
        </section>
      <% end %>
    </article>
    """
  end

  attr :effects, :list, required: true

  def effect_rows(assigns) do
    ~H"""
    <dl :if={@effects != []} class="skill-tooltip-effects">
      <div :for={effect <- @effects} class="skill-tooltip-effect" data-effect={effect.key} data-tone={effect.tone}>
        <dt><.icon name={effect_icon(effect)} class="skill-tooltip-effect-icon" /><span>{effect.label}</span></dt>
        <dd><.value terms={effect.value} /></dd>
      </div>
    </dl>
    """
  end

  attr :entries, :list, required: true

  def metadata_rows(assigns) do
    ~H"""
    <footer :if={@entries != []} class="skill-tooltip-meta">
      <span :for={entry <- @entries} class="skill-tooltip-meta-entry" data-kind={entry.kind}>
        <.icon name={entry.icon} class="skill-tooltip-meta-icon" />{entry.label}
      </span>
    </footer>
    """
  end

  attr :terms, :list, required: true

  defp value(assigns) do
    ~H"""
    <span
      :for={{term, index} <- Enum.with_index(@terms)}
      class={["skill-tooltip-term", term.unit && String.starts_with?(term.unit, "%") && "is-percentage"]}
    >
      <span :if={index > 0} class="skill-tooltip-plus">+</span><strong>{Copy.number(term.amount)}{if percentage?(term), do: "%"}</strong><span
        :if={unit_label(term) != ""}
        class="skill-tooltip-unit"
      >{" "}{unit_label(term)}</span>
    </span>
    """
  end

  defp percentage?(%{unit: unit}), do: is_binary(unit) && String.starts_with?(unit, "%")

  defp effect_icon(%{key: :stun}), do: "game-stun"
  defp effect_icon(%{key: :cleanse}), do: "game-refresh"
  defp effect_icon(%{key: :rules}), do: "game-battle-log"

  defp effect_icon(%{tone: tone}) do
    "game-" <>
      Map.fetch!(
        %{
          damage: "damage",
          health: "health",
          energy: "energy",
          armor: "armor",
          power: "power",
          attack: "attack",
          chance: "chance",
          status: "clock"
        },
        tone
      )
  end

  defp unit_label(%{unit: nil}), do: ""

  defp unit_label(term),
    do: if(percentage?(term), do: term.unit |> String.trim_leading("%") |> String.trim(), else: term.unit)

  defp metadata(skill) do
    passive = Map.get(skill, :passive, false)
    cost = Map.get(skill, :mp_cost) || 0
    cooldown = Map.get(skill, :cooldown) || 0
    energy = if skill.code == "pulse_nova", do: "#{cost} Energy / pulse", else: "#{cost} Energy"
    timing = if cooldown == 0, do: "No cooldown", else: "#{cooldown} #{if cooldown == 1, do: "turn", else: "turns"}"
    damage? = Enum.any?(Copy.describe(skill).effects, &(&1.tone == :damage))

    Enum.reject(
      [
        if(!passive || cost > 0, do: %{kind: :energy, icon: "game-energy", label: energy}),
        if(!passive || !is_nil(Map.get(skill, :cooldown)), do: %{kind: :cooldown, icon: "game-clock", label: timing}),
        if(damage? && skill.code != "rearm" && skill.code != "spell_steal",
          do: damage_metadata(Map.get(skill, :damage_type))
        )
      ],
      &is_nil/1
    )
  end

  defp damage_metadata(type) do
    case GH.damage_type_label(type) do
      nil -> nil
      label -> %{kind: type, icon: "game-damage", label: "#{label} Damage"}
    end
  end

  defp upgrade_for(nil, _), do: nil

  defp upgrade_for(next, skill) do
    before = Copy.describe(skill)
    after_content = Copy.describe(next)
    previous = Map.new(before.effects, &{&1.key, &1})

    changes =
      Enum.flat_map(after_content.effects, fn effect ->
        case previous[effect.key] do
          %{value: value} when value == effect.value ->
            []

          %{value: value} ->
            {old, new} = changed_values(value, effect.value)
            [%{key: effect.key, label: effect.label, tone: effect.tone, before: old, after: new}]

          nil ->
            [
              %{
                key: effect.key,
                label: effect.label,
                tone: effect.tone,
                before: "—",
                after: Copy.value_text(effect.value)
              }
            ]
        end
      end)

    changes =
      changes ++
        Enum.flat_map([{:mp_cost, "Energy cost"}, {:cooldown, "Cooldown"}], fn {key, label} ->
          old = Map.get(skill, key) || 0
          new = Map.get(next, key) || 0
          tone = if key == :mp_cost, do: :energy, else: :status

          if old == new,
            do: [],
            else: [%{key: key, label: label, tone: tone, before: Copy.number(old), after: Copy.number(new)}]
        end)

    changes =
      if Map.get(skill, :damage_type) == Map.get(next, :damage_type),
        do: changes,
        else:
          changes ++
            [
              %{
                key: :damage_type,
                label: "Damage type",
                tone: :damage,
                before: GH.damage_type_label(Map.get(skill, :damage_type)) || "—",
                after: GH.damage_type_label(Map.get(next, :damage_type)) || "—"
              }
            ]

    changes =
      if before.notes == after_content.notes,
        do: changes,
        else:
          changes ++
            [
              %{
                key: :rules,
                label: "Rules",
                tone: :status,
                before: Enum.join(before.notes, " "),
                after: Enum.join(after_content.notes, " ")
              }
            ]

    %{rank: next.level, changes: changes}
  end

  defp changed_values(old, new) when length(old) == length(new) do
    pairs = Enum.zip(old, new) |> Enum.reject(fn {a, b} -> a == b end)

    case pairs do
      [{%{amount: before, unit: unit}, %{amount: after_value, unit: unit}}] ->
        suffix = if unit && String.starts_with?(unit, "%"), do: "%", else: ""
        {Copy.number(before) <> suffix, Copy.number(after_value) <> suffix}

      _ ->
        {Copy.value_text(Enum.map(pairs, &elem(&1, 0))), Copy.value_text(Enum.map(pairs, &elem(&1, 1)))}
    end
  end

  defp changed_values(old, new), do: {Copy.value_text(old), Copy.value_text(new)}
end
