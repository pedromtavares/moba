defmodule MobaWeb.V2.Layouts do
  use Phoenix.Component

  import Phoenix.Controller, only: [get_csrf_token: 0]

  import MobaWeb.V2.Components.LayoutComponents

  alias MobaWeb.LayoutView

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

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <%= if LayoutView.show_sidebar?(assigns) do %>
      <div class="row">
        <.sidebar current_player={@current_player} sidebar_code={@sidebar_code} />
        <div class="col">
          <.flash_group flash={@flash} />
          {render_slot(@inner_block)}
          <%= if LayoutView.show_footer?(assigns) do %>
            <.footer_stats />
          <% end %>
        </div>
      </div>
    <% else %>
      <.flash_group flash={@flash} />
      {render_slot(@inner_block)}
    <% end %>
    """
  end

  defp flash_group(assigns) do
    ~H"""
    <%= if @flash != %{} do %>
      <div class="row mt-2">
        <div class="col">
          <%= if msg = @flash["info"] do %>
            <div class="alert alert-info alert-dismissible" role="alert">
              <button type="button" class="close" data-dismiss="alert"><span>×</span></button>
              {msg}
            </div>
          <% end %>
          <%= if msg = @flash["error"] do %>
            <div class="alert alert-danger alert-dismissible" role="alert">
              <button type="button" class="close" data-dismiss="alert"><span>×</span></button>
              {msg}
            </div>
          <% end %>
        </div>
      </div>
    <% end %>
    """
  end
end
