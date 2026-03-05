defmodule MobaWeb.V2.Components.LayoutComponents do
  @moduledoc """
  Layout function components for BrowserMOBA v2.

  Replaces v1's SidebarLive with a function component using the same markup.
  """
  use Phoenix.Component

  alias Moba.Admin

  use Phoenix.VerifiedRoutes,
    endpoint: MobaWeb.Endpoint,
    router: MobaWeb.Router,
    statics: MobaWeb.static_paths()

  # -------------------------------------------------------------------
  # Sidebar
  # -------------------------------------------------------------------

  @doc """
  Renders the navigation sidebar — exact mirror of v1's sidebar.html.heex.
  """
  attr :current_player, :map, required: true
  attr :sidebar_code, :string, default: nil

  def sidebar(assigns) do
    ~H"""
    <div class="sidebar-nav-container">
      <div class="sidebar-nav d-none d-md-flex">
        <.link
          navigate={~p"/v2/base"}
          data-toggle="tooltip"
          data-tippy-placement="right"
          data-tippy-arrow={false}
          title="<h3 class='ml-2 mr-2'>Training</h3>"
          class={sidebar_class(["training", "base"], %{sidebar_code: @sidebar_code})}
        >
          <i class="fa-duotone fa-sword"></i>
        </.link>
        <%= if @current_player.user_id do %>
          <.link
            navigate={~p"/arena"}
            data-toggle="tooltip"
            data-tippy-placement="right"
            data-tippy-arrow={false}
            title="<h3 class='ml-2 mr-2'>Arena</h3>"
            class={sidebar_class("arena", %{sidebar_code: @sidebar_code})}
          >
            <i class="fa-duotone fa-swords"></i>
          </.link>
        <% else %>
          <a
            href="javascript:;"
            class="no-action"
            data-toggle="tooltip"
            data-tippy-placement="right"
            title="<h3 class='ml-2 mr-2'>Arena (locked)<br/><em class='font-15'>you must create an account</em></h3>"
          >
            <i class="fa-duotone fa-swords"></i>
          </a>
        <% end %>
        <%= if guest?(@current_player) do %>
          <.link
            navigate={~p"/users/register"}
            data-toggle="tooltip"
            data-tippy-placement="right"
            data-tippy-arrow={false}
            title="<h3 class='ml-2 mr-2'>Create an Account</h3>"
            id="create-account-link"
          >
            <i class="fa fa-user-plus"></i>
          </.link>
        <% else %>
          <.link
            navigate={~p"/v2/player/#{@current_player.id}"}
            data-toggle="tooltip"
            data-tippy-placement="right"
            data-tippy-arrow={false}
            title="<h3 class='ml-2 mr-2'>Profile</h3>"
            class={sidebar_class("user", %{sidebar_code: @sidebar_code})}
          >
            <i class="fa-duotone fa-helmet-battle"></i>
          </.link>
          <.link
            navigate={~p"/v2/tavern"}
            data-toggle="tooltip"
            data-tippy-placement="right"
            data-tippy-arrow={false}
            title="<h3 class='ml-2 mr-2'>Tavern</h3>"
            class={sidebar_class("tavern", %{sidebar_code: @sidebar_code})}
          >
            <i class="fa-duotone fa-dungeon"></i>
          </.link>
        <% end %>
        <.link
          navigate={~p"/v2/community"}
          data-toggle="tooltip"
          data-tippy-placement="right"
          data-tippy-arrow={false}
          title="<h3 class='ml-2 mr-2'>Community</h3>"
          class={sidebar_class("community", %{sidebar_code: @sidebar_code})}
        >
          <i class="fa-duotone fa-globe"></i>
        </.link>
        <.link
          navigate={~p"/v2/library"}
          data-toggle="tooltip"
          data-tippy-placement="right"
          data-tippy-arrow={false}
          title="<h3 class='ml-2 mr-2'>Game Manual</h3>"
          class={sidebar_class("library", %{sidebar_code: @sidebar_code})}
          id="game-manual"
        >
          <i class="fa-duotone fa-book-sparkles"></i>
        </.link>
        <%= if @current_player.user && @current_player.user.is_admin do %>
          <a href="/admin">
            <i class="fa-duotone fa-user-shield"></i>
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
                    <.link navigate={~p"/v2/training"} class="nav-link">
                      <i class="fa fa-sword"></i>
                    </.link>
                  <% end %>
                  <.link navigate={~p"/v2/base"} class="nav-link">
                    <i class="fa fa-home"></i>
                  </.link>
                  <%= if @current_player do %>
                    <%= if length(@current_player.hero_collection) > 0 do %>
                      <.link navigate={~p"/arena"} class="nav-link">
                        <i class="fa fa-swords"></i>
                      </.link>
                    <% end %>
                    <%= if @current_player.user_id do %>
                      <.link navigate={~p"/v2/player/#{@current_player.id}"} class="nav-link">
                        <i class="fa fa-helmet-battle"></i>
                      </.link>
                      <.link navigate={~p"/v2/community"} class="nav-link">
                        <i class="fa fa-globe"></i>
                      </.link>
                      <.link navigate={~p"/v2/tavern"} class="nav-link">
                        <i class="fa fa-dungeon"></i>
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
    masters = (server_data && server_data.masters_count) || 0
    grandmasters = (server_data && server_data.grandmasters_count) || 0
    undefeated = (server_data && server_data.undefeated_count) || 0

    %{
      active: format_number(Admin.active_players_count()),
      heroes: format_number(Admin.trained_heroes_count()),
      matches: format_number(Admin.matches_count()),
      masters: format_number(masters),
      grandmasters: format_number(grandmasters),
      undefeated: format_number(undefeated)
    }
  end

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
