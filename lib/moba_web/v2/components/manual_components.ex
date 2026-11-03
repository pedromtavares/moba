defmodule MobaWeb.V2.Components.ManualComponents do
  use Phoenix.Component

  import MobaWeb.CoreComponents, only: [icon: 1]
  import Phoenix.HTML, only: [raw: 1]
  alias MobaWeb.V2.Components.{GameHelpers, TooltipComponents}

  attr :avatars, :list, required: true

  def avatar_reference(assigns) do
    ~H"""
    <div class="manual-avatar-stage">
      <article
        :for={{avatar, index} <- Enum.with_index(@avatars)}
        data-manual-detail="avatar"
        data-code={avatar.code}
        id={"manual-avatar-#{avatar.code}"}
        hidden={index != 0}
        class="manual-avatar-detail"
        style={"--manual-art: url(#{GameHelpers.background_url(avatar)})"}
      >
        <div class="manual-avatar-identity">
          <span class="manual-kicker">
            <img src={"/images/#{avatar.role}_icon.png"} alt="" />{GameHelpers.role_name(avatar.role)}
          </span>
          <h2>{avatar.name}</h2>
          <p>{avatar.description}</p>
          <dl class="manual-avatar-stats">
            <div :for={stat <- avatar_stats(avatar)} data-stat={stat.code}>
              <dt><.icon name={"game-#{stat.code}"} class="manual-stat-icon" />{stat.label}</dt>
              <dd>{stat.value}<small :if={stat.growth}>+{stat.growth} / level</small></dd>
            </div>
          </dl>
        </div>
        <aside class="manual-ultimate" aria-label={"#{avatar.name} ultimate"}>
          <.ranked_skill levels={avatar.ultimate_ranks} id={"manual-ultimate-#{avatar.code}"} />
        </aside>
      </article>
    </div>
    <div class="manual-roster">
      <header>
        <h3>Choose an avatar</h3>
        <span>{length(@avatars)} avatars</span>
      </header>
      <div class="manual-avatar-grid" role="group" aria-label="Avatar reference roster">
        <button
          :for={{avatar, index} <- Enum.with_index(@avatars)}
          type="button"
          id={"manual-pick-avatar-#{avatar.code}"}
          data-manual-pick="avatar"
          data-code={avatar.code}
          aria-pressed={to_string(index == 0)}
          aria-controls={"manual-avatar-#{avatar.code}"}
        >
          <img src={GameHelpers.image_url(avatar)} alt="" loading="lazy" /><span>{avatar.name}</span>
        </button>
      </div>
    </div>
    """
  end

  attr :skills, :list, required: true

  def skill_reference(assigns) do
    ~H"""
    <div class="manual-reference-layout">
      <div class="manual-reference-picker">
        <div class="manual-resource-grid" aria-label="Skill reference roster">
          <button
            :for={{{skill, _levels}, index} <- Enum.with_index(@skills)}
            id={"manual-pick-skill-#{skill.code}"}
            type="button"
            data-manual-pick="skill"
            data-code={skill.code}
            aria-pressed={to_string(index == 0)}
            aria-controls={"manual-skill-#{skill.code}"}
          >
            <img src={GameHelpers.image_url(skill)} alt="" loading="lazy" /><strong>{skill.name}</strong>
            <small><.icon name="game-energy" class="manual-cost-icon" />{skill.mp_cost || 0}</small>
          </button>
        </div>
      </div>
      <aside class="manual-reference-detail" aria-label="Selected skill">
        <section
          :for={{{skill, levels}, index} <- Enum.with_index(@skills)}
          id={"manual-skill-#{skill.code}"}
          data-manual-detail="skill"
          data-code={skill.code}
          hidden={index != 0}
        >
          <.ranked_skill levels={levels} id={"manual-skill-ranks-#{skill.code}"} />
        </section>
      </aside>
    </div>
    """
  end

  attr :levels, :list, required: true
  attr :id, :string, required: true

  def ranked_skill(assigns) do
    ~H"""
    <div :if={@levels != []} id={@id} data-manual-ranked>
      <div class="manual-ranks" role="tablist" aria-label={"#{hd(@levels).name} ranks"}>
        <button
          :for={{skill, index} <- Enum.with_index(@levels)}
          type="button"
          role="tab"
          id={"#{@id}-tab-#{skill.level}"}
          data-manual-rank={skill.level}
          aria-selected={to_string(index == 0)}
          aria-controls={"#{@id}-rank-#{skill.level}"}
          tabindex={if index == 0, do: "0", else: "-1"}
        >
          Rank {skill.level}
        </button>
      </div>
      <div
        :for={{skill, index} <- Enum.with_index(@levels)}
        id={"#{@id}-rank-#{skill.level}"}
        data-manual-rank-panel={skill.level}
        role="tabpanel"
        aria-labelledby={"#{@id}-tab-#{skill.level}"}
        hidden={index != 0}
        class="game-tooltip-content manual-inline-card"
      >
        {raw(TooltipComponents.skill_tooltip(skill))}
      </div>
    </div>
    """
  end

  defp avatar_stats(avatar) do
    for {code, label, field, growth} <- [
          {"health", "Health", :total_hp, :hp_per_level},
          {"energy", "Energy", :total_mp, :mp_per_level},
          {"attack", "Attack", :atk, :atk_per_level},
          {"power", "Power", :power, nil},
          {"armor", "Armor", :armor, nil},
          {"speed", "Speed", :speed, nil}
        ],
        do: %{code: code, label: label, value: Map.get(avatar, field), growth: growth && Map.get(avatar, growth)}
  end
end
