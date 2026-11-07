defmodule MobaWeb.V2.Components.SeasonScoreTooltip do
  use Phoenix.Component
  import MobaWeb.CoreComponents, only: [icon: 1]
  alias Moba.Game.SeasonScore

  def render(player) do
    %{
      player: player,
      training_points: SeasonScore.training_points(player),
      streak_points: SeasonScore.streak_points(player),
      immortal_bonus: SeasonScore.immortal_bonus(player),
      score: SeasonScore.total(player)
    }
    |> card()
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  defp card(assigns) do
    ~H"""
    <article class="skill-tooltip season-score-tooltip">
      <header class="skill-tooltip-heading">
        <.icon name="game-season-score" class="season-score-tooltip-emblem" />
        <h3>Season Score</h3>
      </header>
      <dl class="skill-tooltip-effects">
        <div class="skill-tooltip-effect" data-score-source="training" data-tone="armor">
          <dt>
            <img class="season-score-rank-icon" src={"/images/pve/#{@player.pve_tier || 0}.png"} alt="" />
            <span>
              {Moba.pve_tiers()[@player.pve_tier || 0]}
            </span>
          </dt>
          <dd><strong>{@training_points}</strong></dd>
        </div>
        <div class="skill-tooltip-effect" data-score-source="arena" data-tone="attack">
          <dt><.icon name="game-swords" class="skill-tooltip-effect-icon" /><span>Arena Rating</span></dt>
          <dd><strong>{@player.pvp_points || 0}</strong></dd>
        </div>
        <div class="skill-tooltip-effect" data-score-source="streak" data-tone="power">
          <dt>
            <.icon name="game-trophy" class="skill-tooltip-effect-icon" />
            <span>
              Best Immortal Streak<small class="season-score-streak-rate">{@player.best_immortal_streak || 0} {if @player.best_immortal_streak == 1, do: "day", else: "days"} at 20/day</small>
            </span>
          </dt>
          <dd><strong>{@streak_points}</strong></dd>
        </div>
        <div :if={@immortal_bonus > 0} class="skill-tooltip-effect" data-score-source="immortal" data-tone="armor">
          <dt><.icon name="game-trophy" class="skill-tooltip-effect-icon" /><span>The Immortal</span></dt>
          <dd><strong>+{@immortal_bonus}</strong></dd>
        </div>
      </dl>
      <footer class="season-score-tooltip-total"><span>Total</span><strong>{@score}</strong></footer>
    </article>
    """
  end
end
