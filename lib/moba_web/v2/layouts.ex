defmodule MobaWeb.V2.Layouts do
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  import Phoenix.Controller, only: [get_csrf_token: 0]

  import MobaWeb.V2.Components.LayoutComponents
  import MobaWeb.CoreComponents, only: [analytics: 1]
  import MobaWeb.Preview, only: [preview_path: 2]

  use Phoenix.VerifiedRoutes,
    endpoint: MobaWeb.Endpoint,
    router: MobaWeb.Router,
    statics: MobaWeb.static_paths()

  embed_templates "layouts/*"

  def live(assigns) do
    ~H"""
    {@inner_content}
    <.feedback :if={@preview} flash={@flash} />
    <%= if @preview && assigns[:current_player] && @current_player.user_id do %>
      {live_render(@socket, MobaWeb.V2.DuelChallengeLive,
        id: "duel-challenges",
        session: %{"player_id" => @current_player.id},
        layout: false
      )}
    <% end %>
    """
  end

  attr :flash, :map, required: true

  def feedback(assigns) do
    ~H"""
    <div id="game-feedback" class="game-feedback">
      <div
        :for={kind <- [:info, :error]}
        :if={Phoenix.Flash.get(@flash, kind)}
        id={"game-feedback-#{kind}"}
        class="game-toast"
        data-kind={kind}
        role={if kind == :error, do: "alert", else: "status"}
      >
        <span class="game-toast-mark" aria-hidden="true">{if kind == :info, do: "✓", else: "!"}</span>
        <p>{Phoenix.Flash.get(@flash, kind)}</p>
        <button type="button" phx-click="lv:clear-flash" phx-value-key={kind} aria-label="Dismiss notification">×</button>
      </div>
      <div
        id="game-connection-status"
        class="game-toast game-connection-status"
        role="status"
        style="display:none"
        phx-disconnected={JS.show()}
        phx-connected={JS.hide()}
      >
        <span class="game-toast-mark" aria-hidden="true">↻</span>
        <p>Connection lost. Reconnecting…</p>
      </div>
    </div>
    """
  end

  @doc """
  Renders the v2 app layout, mirroring v1's live.html.heex structure.

  Shows sidebar + content column when show_sidebar? is true (player with hero_collection),
  otherwise renders inner content directly.

  ## Examples

      <Layouts.app flash={@flash} current_player={@current_player} current_hero={@current_hero}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true
  attr :current_player, :map, default: nil
  attr :current_hero, :map, default: nil
  attr :sidebar_code, :string, default: nil
  attr :hide_footer, :boolean, default: false
  attr :hide_sidebar, :boolean, default: false
  attr :preview, :boolean, default: false

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class={@preview && "game-page"} id={@preview && "game-page"}>
      <.atmosphere :if={@preview} />
      <%= if show_sidebar?(assigns) do %>
        <div class="row">
          <.sidebar current_player={@current_player} sidebar_code={@sidebar_code} preview={@preview} />
          <div class="col">
            {render_slot(@inner_block)}
            <%= if show_footer?(assigns) do %>
              <.footer_stats />
            <% end %>
          </div>
        </div>
      <% else %>
        {render_slot(@inner_block)}
      <% end %>
    </div>
    """
  end

  def atmosphere(assigns) do
    ~H"""
    <div class="base-atmosphere" aria-hidden="true">
      <span class="base-mist"></span>
    </div>
    <span class="base-embers" aria-hidden="true"></span>
    """
  end

  defp show_sidebar?(assigns) do
    assigns[:current_player] && !assigns[:hide_sidebar] && length(assigns[:current_player].hero_collection) > 0
  end

  defp show_footer?(assigns) do
    !assigns[:hide_footer] && assigns[:current_player] && assigns[:current_player].user_id &&
      (!assigns[:preview] || assigns[:sidebar_code] == "community")
  end
end
