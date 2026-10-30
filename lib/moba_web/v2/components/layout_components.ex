defmodule MobaWeb.V2.Components.LayoutComponents do
  @moduledoc """
  Layout function components for BrowserMOBA v2.

  Replaces v1's SidebarLive with a function component using the same markup.
  """
  use Phoenix.Component
  import MobaWeb.CoreComponents, only: [icon: 1]
  import MobaWeb.Preview, only: [preview_path: 2]

  alias Moba.Admin

  use Phoenix.VerifiedRoutes,
    endpoint: MobaWeb.Endpoint,
    router: MobaWeb.Router,
    statics: MobaWeb.static_paths()

  # -------------------------------------------------------------------
  # Sidebar
  # -------------------------------------------------------------------

  @doc """
  Renders the navigation sidebar with BrowserMOBA's custom emblems.
  """
  attr :current_player, :map, required: true
  attr :sidebar_code, :string, default: nil
  attr :preview, :boolean, default: false

  def sidebar(assigns) do
    ~H"""
    <div class="sidebar-nav-container">
      <div
        class="sidebar-nav d-none d-md-flex"
        id={@preview && "game-sidebar"}
        role="navigation"
        aria-label="Main navigation"
      >
        <.link
          navigate={preview_path(assigns, ~p"/base")}
          aria-label="Base"
          data-toggle={if !@preview, do: "tooltip"}
          data-tippy-placement="right"
          data-tippy-arrow={false}
          title={if !@preview, do: "<h3 class='ml-2 mr-2'>Training</h3>"}
          class={sidebar_class(["training", "base"], %{sidebar_code: @sidebar_code})}
        >
          <.icon name="nav-base" class="" />
          <span :if={@preview} class="sidebar-label">Base</span>
        </.link>
        <%= if @current_player.user_id do %>
          <.link
            navigate={preview_path(assigns, ~p"/arena")}
            aria-label="Arena"
            data-toggle={if !@preview, do: "tooltip"}
            data-tippy-placement="right"
            data-tippy-arrow={false}
            title={if !@preview, do: "<h3 class='ml-2 mr-2'>Arena</h3>"}
            class={sidebar_class("arena", %{sidebar_code: @sidebar_code})}
          >
            <.icon name="nav-arena" class="" />
            <span :if={@preview} class="sidebar-label">Arena</span>
          </.link>
        <% else %>
          <a
            href="javascript:;"
            class="no-action"
            data-toggle={if !@preview, do: "tooltip"}
            data-tippy-placement="right"
            title={
              if !@preview,
                do: "<h3 class='ml-2 mr-2'>Arena (locked)<br/><em class='font-15'>you must create an account</em></h3>"
            }
            aria-label="Arena locked: create an account to play"
          >
            <.icon name="nav-arena" class="" />
            <span :if={@preview} class="sidebar-label">Arena · Locked</span>
          </a>
        <% end %>
        <%= if guest?(@current_player) do %>
          <.link
            navigate={preview_path(assigns, ~p"/users/register")}
            aria-label="Create an account"
            data-toggle={if !@preview, do: "tooltip"}
            data-tippy-placement="right"
            data-tippy-arrow={false}
            title={if !@preview, do: "<h3 class='ml-2 mr-2'>Create an Account</h3>"}
            id="create-account-link"
          >
            <.icon name="nav-join" class="" />
            <span :if={@preview} class="sidebar-label">Join</span>
          </.link>
        <% else %>
          <.link
            navigate={preview_path(assigns, ~p"/player/#{@current_player.id}")}
            aria-label="Profile"
            data-toggle={if !@preview, do: "tooltip"}
            data-tippy-placement="right"
            data-tippy-arrow={false}
            title={if !@preview, do: "<h3 class='ml-2 mr-2'>Profile</h3>"}
            class={sidebar_class("user", %{sidebar_code: @sidebar_code})}
          >
            <.icon name="nav-profile" class="" />
            <span :if={@preview} class="sidebar-label">Profile</span>
          </.link>
          <.link
            navigate={preview_path(assigns, ~p"/tavern")}
            aria-label="Tavern"
            data-toggle={if !@preview, do: "tooltip"}
            data-tippy-placement="right"
            data-tippy-arrow={false}
            title={if !@preview, do: "<h3 class='ml-2 mr-2'>Tavern</h3>"}
            class={sidebar_class("tavern", %{sidebar_code: @sidebar_code})}
          >
            <.icon name="nav-tavern" class="" />
            <span :if={@preview} class="sidebar-label">Tavern</span>
          </.link>
        <% end %>
        <.link
          navigate={preview_path(assigns, ~p"/community")}
          aria-label="Community"
          data-toggle={if !@preview, do: "tooltip"}
          data-tippy-placement="right"
          data-tippy-arrow={false}
          title={if !@preview, do: "<h3 class='ml-2 mr-2'>Community</h3>"}
          class={sidebar_class("community", %{sidebar_code: @sidebar_code})}
        >
          <.icon name="nav-community" class="" />
          <span :if={@preview} class="sidebar-label">Community</span>
        </.link>
        <.link
          navigate={preview_path(assigns, ~p"/library")}
          aria-label="Game Manual"
          data-toggle={if !@preview, do: "tooltip"}
          data-tippy-placement="right"
          data-tippy-arrow={false}
          title={if !@preview, do: "<h3 class='ml-2 mr-2'>Game Manual</h3>"}
          class={sidebar_class("library", %{sidebar_code: @sidebar_code})}
          id="game-manual"
        >
          <.icon name="nav-manual" class="" />
          <span :if={@preview} class="sidebar-label">Game Manual</span>
        </.link>
        <%= if @current_player.user && @current_player.user.is_admin do %>
          <a href="/admin" class={@preview && "sidebar-utility"} aria-label="Admin">
            <.icon name="nav-admin" class="" />
            <span :if={@preview} class="sidebar-label">Admin</span>
          </a>
        <% end %>
      </div>
    </div>
    """
  end

  # -------------------------------------------------------------------
  # Mobile Navigation
  # -------------------------------------------------------------------

  @doc """
  Renders the mobile top navigation bar — exact mirror of v1's _mobile_navigation.html.heex.
  """
  attr :current_player, :map, default: nil
  attr :current_hero, :map, default: nil
  attr :preview, :boolean, default: false

  def mobile_navigation(assigns) do
    ~H"""
    <header id="topnav" class="d-md-none">
      <div class="topbar-menu">
        <div class="container-fluid clean-container">
          <div id="inner-navigation">
            <div class="col-xl-11 margin-auto">
              <div class="row text-center game-nav no-gutters">
                <div class="col d-flex justify-content-center">
                  <%= if @current_hero && is_nil(@current_hero.finished_at) do %>
                    <.link navigate={preview_path(assigns, ~p"/training")} class="nav-link" aria-label="Training">
                      <.icon name="nav-training" class="" />
                    </.link>
                  <% end %>
                  <.link navigate={preview_path(assigns, ~p"/base")} class="nav-link" aria-label="Base">
                    <.icon name="nav-base" class="" />
                  </.link>
                  <%= if @current_player do %>
                    <%= if length(@current_player.hero_collection) > 0 do %>
                      <.link navigate={preview_path(assigns, ~p"/arena")} class="nav-link" aria-label="Arena">
                        <.icon name="nav-arena" class="" />
                      </.link>
                    <% end %>
                    <%= if @current_player.user_id do %>
                      <.link
                        navigate={preview_path(assigns, ~p"/player/#{@current_player.id}")}
                        class="nav-link"
                        aria-label="Profile"
                      >
                        <.icon name="nav-profile" class="" />
                      </.link>
                      <.link navigate={preview_path(assigns, ~p"/community")} class="nav-link" aria-label="Community">
                        <.icon name="nav-community" class="" />
                      </.link>
                      <.link navigate={preview_path(assigns, ~p"/tavern")} class="nav-link" aria-label="Tavern">
                        <.icon name="nav-tavern" class="" />
                      </.link>
                    <% end %>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </header>
    """
  end

  # -------------------------------------------------------------------
  # Footer Stats
  # -------------------------------------------------------------------

  @doc """
  Renders the footer stats bar — exact mirror of v1's stats-footer row.
  """
  def footer_stats(assigns) do
    assigns = assign(assigns, :stats, build_footer_stats())

    ~H"""
    <div class="row stats-footer">
      <div class="col">
        <div class="card dark-bg-lighter mb-0">
          <div class="card-body pb-3 pt-3">
            <div class="row justify-content-center">
              <div class="col text-center">
                <h5><i class="fa fa-swords mr-1"></i>{@stats.matches} matches</h5>
              </div>
              <div class="col text-center">
                <h5><i class="fa fa-users mr-1"></i>{@stats.active} players</h5>
              </div>
              <div class="col text-center">
                <h5><i class="fa fa-helmet-battle mr-1"></i>{@stats.heroes} trained</h5>
              </div>
              <div class="col text-center">
                <h5>
                  <img src="/images/league/5.png" class="mr-1" />{@stats.masters} masters
                </h5>
              </div>
              <div class="col text-center">
                <h5>
                  <img src="/images/league/6.png" class="mr-1" />{@stats.grandmasters} grandmasters
                </h5>
              </div>
              <div class="col text-center">
                <h5>
                  <img src="/images/league/6.png" class="mr-1 undefeated" />{@stats.undefeated} undefeated
                </h5>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp build_footer_stats do
    server_data = Admin.get_server_data()
    masters = server_stat(server_data, :masters_count)
    grandmasters = server_stat(server_data, :grandmasters_count)
    undefeated = server_stat(server_data, :undefeated_count)

    %{
      active: format_number(Admin.active_players_count()),
      heroes: format_number(Admin.trained_heroes_count()),
      matches: format_number(Admin.matches_count()),
      masters: format_number(masters),
      grandmasters: format_number(grandmasters),
      undefeated: format_number(undefeated)
    }
  end

  defp server_stat(server_data, key) when is_map(server_data), do: Map.get(server_data, key, 0)
  defp server_stat(_, _), do: 0

  defp format_number(n) do
    "#{n}"
    |> to_charlist()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.reverse(&1))
    |> Enum.reverse()
    |> Enum.join(",")
  end

  defp guest?(%{user_id: user_id}), do: is_nil(user_id)

  defp sidebar_class(codes, assigns) when is_list(codes) do
    if Enum.member?(codes, assigns[:sidebar_code]), do: "active", else: ""
  end

  defp sidebar_class(code, assigns) do
    if assigns[:sidebar_code] == code, do: "active", else: ""
  end
end
