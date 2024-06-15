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

  def static_paths, do: ~w(assets css fonts images resources js favicon.ico robots.txt ads.txt .well-known)

  def router do
    quote do
      use Phoenix.Router

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
        formats: [:html, :json],
        layouts: [html: MobaWeb.Layouts]

      import Plug.Conn
      import MobaWeb.Gettext
      import Phoenix.LiveView.Controller, only: [live_render: 3, live_render: 2]

      alias MobaWeb.Router.Helpers, as: Routes

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView, layout: {MobaWeb.LayoutView, :live}

      alias Moba.{Game, Accounts, Engine, Utils}

      import MobaWeb.Gettext

      unquote(html_helpers())

      defguard is_connected?(socket) when socket.transport_pid != nil
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
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

  defp html_helpers do
    quote do
      # HTML escaping functionality
      import Phoenix.HTML
      # Core UI components and translation
      import MobaWeb.Gettext

      alias MobaWeb.ErrorHelpers

      # Shortcut for generating JS commands
      alias Phoenix.LiveView.JS

      use PhoenixHTMLHelpers

      alias MobaWeb.Router.Helpers, as: Routes

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
