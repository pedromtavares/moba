defmodule MobaWeb.Router do
  use MobaWeb, :router
  use Pow.Phoenix.Router
  use Pow.Extension.Phoenix.Router, otp_app: :moba
  import Phoenix.LiveDashboard.Router

  if Mix.env() == :dev do
    forward "/sent_emails", Bamboo.SentEmailViewerPlug
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :root_layout do
    plug :put_root_layout, {MobaWeb.LayoutView, :root}
  end

  pipeline :pow_layout do
    plug :put_pow_layout, {MobaWeb.LayoutView, :root}
  end

  pipeline :protected do
    plug Pow.Plug.RequireAuthenticated,
      error_handler: Pow.Phoenix.PlugErrorHandler
  end

  pipeline :player_protected do
    plug MobaWeb.PlayerAuth
  end

  pipeline :admin_protected do
    plug MobaWeb.AdminAuth
  end

  scope "/" do
    pipe_through [:browser, :pow_layout]

    pow_routes()
    pow_extension_routes()

    get "/start", MobaWeb.GameController, :start
    post "/start", MobaWeb.GameController, :create

    get "/", MobaWeb.GameController, :index
  end

  scope "/", MobaWeb do
    pipe_through [:browser, :root_layout]

    live "/battles/:id", BattleLive
  end

  scope "/", MobaWeb do
    pipe_through [:browser, :root_layout, :player_protected]

    live_session :default, on_mount: MobaWeb.PlayerLiveAuth do
      live "/invoke", CreateLive

      live "/training", TrainingLive

      live "/battles", BattlesLive

      live "/base", DashboardLive

      live "/arena", ArenaLive
      live "/arena/:id", DuelLive

      live "/user/:id", UserLive
      live "/player/:player_id", UserLive, :show, as: :player

      live "/hero/:id", HeroLive

      live "/tavern", TavernLive

      live "/community", CommunityLive

      live "/library", LibraryLive
    end
  end

  scope "/admin", MobaWeb do
    pipe_through [:browser, :protected, :admin_protected]

    resources "/skills", Admin.SkillController
    resources "/items", Admin.ItemController
    resources "/avatars", Admin.AvatarController
    resources "/users", Admin.UserController
    resources "/seasons", Admin.SeasonController
    resources "/skins", Admin.SkinController

    live_dashboard "/dashboard", metrics: MobaWeb.Telemetry, ecto_repos: [Moba.Repo]

    get "/", Admin.SkillController, :root
  end

  defp put_pow_layout(conn, layout), do: put_private(conn, :phoenix_layout, layout)
end
