defmodule MobaWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, views, channels and so on.

  This can be used in your application as:

      use MobaWeb, :controller
      use MobaWeb, :view

  The definitions below will be executed for every view,
  controller, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define any helper function in modules
  and import those modules here.
  """

  def subscribe(channel) do
    Phoenix.PubSub.subscribe(Moba.PubSub, channel)
  end

  def broadcast(channel, event, payload) do
    Phoenix.PubSub.broadcast(Moba.PubSub, channel, {event, payload})
  end

  def controller do
    quote do
      use Phoenix.Controller, namespace: MobaWeb

      import Plug.Conn
      import MobaWeb.Gettext
      alias MobaWeb.Router.Helpers, as: Routes
      import Phoenix.LiveView.Controller, only: [live_render: 3, live_render: 2]
    end
  end

  def view do
    quote do
      use Phoenix.View,
        root: "lib/moba_web/templates",
        namespace: MobaWeb

      # Import convenience functions from controllers
      import Phoenix.Controller, only: [get_flash: 1, get_flash: 2, view_module: 1]
      import Phoenix.LiveView.Helpers

      # Use all HTML functionality (forms, tags, etc)
      use Phoenix.HTML

      import MobaWeb.ErrorHelpers
      # import MobaWeb.GameHelpers
      import MobaWeb.Gettext
      alias MobaWeb.Router.Helpers, as: Routes
      alias MobaWeb.GameHelpers, as: GH
    end
  end

  def router do
    quote do
      use Phoenix.Router
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
      import MobaWeb.Gettext
    end
  end

  def mailer_view do
    quote do
      use Phoenix.View,
        root: "lib/moba_web/templates",
        namespace: MobaWeb

      use Phoenix.HTML
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
