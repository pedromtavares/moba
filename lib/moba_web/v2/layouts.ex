defmodule MobaWeb.V2.Layouts do
  use Phoenix.Component

  import Phoenix.Controller, only: [get_csrf_token: 0]

  import MobaWeb.V2.Components.LayoutComponents

  use Phoenix.VerifiedRoutes,
    endpoint: MobaWeb.Endpoint,
    router: MobaWeb.Router,
    statics: MobaWeb.static_paths()

  embed_templates "layouts/*"

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

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <%= if show_sidebar?(assigns) do %>
      <div class="row">
        <.sidebar current_player={@current_player} sidebar_code={@sidebar_code} />
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
    """
  end

  defp show_sidebar?(assigns) do
    assigns[:current_player] && !assigns[:hide_sidebar] && length(assigns[:current_player].hero_collection) > 0
  end

  defp show_footer?(assigns) do
    !assigns[:hide_footer] && assigns[:current_player] && assigns[:current_player].user_id
  end

end
