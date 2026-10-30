defmodule MobaWeb.V2.Components.ProgressionComponents do
  use Phoenix.Component

  alias Moba.Game
  alias MobaWeb.V2.Components.GameHelpers, as: GH
  import MobaWeb.Preview, only: [preview_path: 2]

  attr :hero, :map, required: true
  attr :player, :map, required: true
  attr :quest, :map, default: nil

  def training_completion(assigns) do
    assigns =
      assign(assigns,
        preview: true,
        qualified: assigns.hero.league_tier >= Moba.platinum_league_tier()
      )

    ~H"""
    <section
      id="training-completion"
      class="training-completion"
      data-outcome={
        cond do
          @quest -> "rank-up"
          @qualified -> "qualified"
          true -> "retry"
        end
      }
      data-league={@hero.league_tier}
      aria-labelledby="training-completion-title"
    >
      <div class="completion-emblem" aria-hidden="true">
        <img src={if @quest, do: "/images/pve/#{@player.pve_tier}.png", else: "/images/league/#{@hero.league_tier}.png"} />
      </div>
      <div class="completion-heading">
        <p class="completion-eyebrow">{if @quest, do: "Rank up", else: "Training complete"}</p>
        <h1 id="training-completion-title">{if @quest, do: @quest.title, else: Moba.leagues()[@hero.league_tier]}</h1>
        <p class="completion-description">
          <%= cond do %>
            <% @quest -> %>
              {@quest.description}
            <% @qualified -> %>
              {@hero.name} is ready for the Arena.
            <% true -> %>
              Reach Platinum League to bring your hero to the Arena.
          <% end %>
        </p>
        <div :if={@quest} id="completion-shards" class="completion-shards">
          <span aria-hidden="true">◆</span> +{@quest.prize} <span>Shards earned</span>
        </div>
      </div>
      <div class="completion-actions">
        <.link
          id="completion-continue"
          navigate={
            preview_path(
              assigns,
              cond do
                @quest && is_nil(@player.user_id) -> "/arena"
                @quest || @qualified -> "/base"
                true -> "/invoke"
              end
            )
          }
          class="btn completion-primary"
        >
          {cond do
            @quest && is_nil(@player.user_id) -> "Enter the Arena"
            @quest || @qualified -> "Return to Base"
            true -> "Train again"
          end}
          <span aria-hidden="true">→</span>
        </.link>
        <button
          :if={@quest}
          id="completion-view-rewards"
          type="button"
          class="btn completion-rewards"
          data-toggle="modal"
          data-target="#pve-tier-rewards"
        >
          View rewards
        </button>
      </div>
      <dl class="completion-stats">
        <div>
          <dt>League reached</dt>
          <dd>{Moba.leagues()[@hero.league_tier]}</dd>
        </div>
        <div>
          <dt>Total farm</dt>
          <dd>{GH.farming_amount_label(@hero.total_xp_farm + @hero.total_gold_farm)}</dd>
        </div>
        <div>
          <dt>Training time</dt>
          <dd>{GH.minutes_label(GH.finished_time(@hero), true)} <small>min</small></dd>
        </div>
      </dl>
    </section>
    """
  end

  attr :tier, :integer, required: true
  attr :earned, :boolean, default: false

  def progression_rewards(assigns) do
    assigns = assign(assigns, quest: Game.get_quest(assigns.tier), preview: true)

    ~H"""
    <div
      id="pve-tier-rewards"
      class="modal fade progression-rewards"
      tabindex="-1"
      role="dialog"
      aria-labelledby="pve-tier-rewards-label"
      aria-describedby="progression-requirement"
      data-tier={@tier}
      data-earned={to_string(@earned)}
    >
      <div class="modal-dialog modal-dialog-centered">
        <div class="modal-content">
          <button
            id="progression-close"
            type="button"
            class="progression-close"
            data-dismiss="modal"
            aria-label="Close rewards"
          >
            ×
          </button>
          <div class="progression-heading">
            <img src={"/images/pve/#{@tier}.png"} alt="" />
            <div>
              <p class="completion-eyebrow">{if @earned, do: "Rank unlocked", else: "Next rank"}</p>
              <h2 id="pve-tier-rewards-label">{Moba.pve_tiers()[@tier]}</h2>
              <p id="progression-requirement">{@quest.description}</p>
            </div>
          </div>
          <.link id="progression-shards" navigate={preview_path(assigns, "/tavern")} class="progression-shards">
            <span class="progression-shard-symbol" aria-hidden="true">◆</span>
            <strong>+{@quest.prize}</strong>
            <span>{if @earned, do: "Shards earned", else: "Shards on rank up"}</span>
            <span class="progression-shards-link">Tavern <span aria-hidden="true">→</span></span>
          </.link>
          <dl class="progression-details">
            <div id="progression-difficulty">
              <dt>Training difficulty</dt>
              <dd>{Map.get(@quest, :difficulty) || Game.get_quest(7).difficulty}</dd>
            </div>
            <div id="progression-farming">
              <dt>Farm per turn</dt>
              <dd>{GH.farming_per_turn_label(@tier)}</dd>
            </div>
            <div id="progression-max-league">
              <dt>Maximum league</dt>
              <dd>{Map.get(@quest, :max_league) || Game.get_quest(7).max_league}</dd>
            </div>
            <div :if={Map.get(@quest, :training_bonus)} id="progression-bonus">
              <dt>Training bonus</dt>
              <dd>{@quest.training_bonus}</dd>
            </div>
          </dl>
          <div class="progression-footer">
            <button id="progression-dismiss" type="button" class="btn completion-primary" data-dismiss="modal">
              {if @earned, do: "Continue", else: "Got it"}
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
