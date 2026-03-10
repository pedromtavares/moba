defmodule MobaWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, components, channels, and so on.

  This can be used in your application as:

      use MobaWeb, :controller
      use MobaWeb, :html

  The definitions below will be executed for every controller,
  component, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  def subscribe(channel) do
    Phoenix.PubSub.subscribe(Moba.PubSub, channel)
  end

  def broadcast(channel, event, payload) do
    Phoenix.PubSub.broadcast(Moba.PubSub, channel, {event, payload})
  end

  def broadcast_from(from, channel, event, payload) do
    Phoenix.PubSub.broadcast_from(Moba.PubSub, from, channel, {event, payload})
  end

  def static_paths, do: ~w(assets css fonts images resources js v2 favicon.ico robots.txt ads.txt .well-known)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:html, :json]

      import Plug.Conn
      use Gettext, backend: MobaWeb.Gettext
      import Phoenix.LiveView.Controller, only: [live_render: 3, live_render: 2]

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView, layout: {MobaWeb.LayoutView, :live}

      alias Moba.{Game, Accounts, Engine, Utils}

      use Gettext, backend: MobaWeb.Gettext

      unquote(html_helpers())

      defguard is_connected?(socket) when socket.transport_pid != nil
    end
  end

  def v2_live_view do
    quote do
      use Phoenix.LiveView

      alias Moba.{Game, Accounts, Engine, Utils}

      use Gettext, backend: MobaWeb.Gettext

      unquote(v2_html_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def v2_live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(v2_html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  def view do
    quote do
      use Phoenix.View,
        root: "lib/moba_web/templates",
        namespace: MobaWeb

      use Phoenix.Component

      # Include shared imports and aliases for views
      unquote(html_helpers())
    end
  end

  def mailer_view do
    quote do
      use Phoenix.View,
        root: "lib/moba_web/templates",
        namespace: MobaWeb

      unquote(html_helpers())
    end
  end

  defp v2_html_helpers do
    quote do
      import Phoenix.HTML

      use Gettext, backend: MobaWeb.Gettext

      import MobaWeb.V2.Components.CoreComponents

      alias MobaWeb.V2.Layouts
      import MobaWeb.V2.Components.CreateComponents
      import MobaWeb.V2.Components.BattleComponents
      import MobaWeb.V2.Components.CommunityComponents
      import MobaWeb.V2.Components.GameComponents
      import MobaWeb.V2.Components.LayoutComponents
      import MobaWeb.V2.Components.LibraryComponents
      import MobaWeb.V2.Components.PvpComponents
      import MobaWeb.V2.Components.ProfileComponents
      import MobaWeb.V2.Components.ShopComponents
      import MobaWeb.V2.Components.TrainingComponents

      alias MobaWeb.V2.Components.GameHelpers, as: GH

      alias Phoenix.LiveView.JS

      alias Moba.{Game, Accounts, Engine, Utils}

      import Moba.Utils

      unquote(verified_routes())
    end
  end

  defp html_helpers do
    quote do
      import Phoenix.HTML
      use Gettext, backend: MobaWeb.Gettext
      import MobaWeb.CoreComponents

      alias MobaWeb.ErrorHelpers

      alias Phoenix.LiveView.JS

      use PhoenixHTMLHelpers

      alias MobaWeb.GameHelpers, as: GH

      alias Moba.{Game, Accounts, Engine, Utils}

      import Moba.Utils

      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: MobaWeb.Endpoint,
        router: MobaWeb.Router,
        statics: MobaWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
