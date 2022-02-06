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
    plug :fetch_flash
    plug :fetch_live_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :root_layout do
    plug :put_root_layout, {MobaWeb.LayoutView, :root}
  end

  pipeline :protected do
    plug Pow.Plug.RequireAuthenticated,
      error_handler: Pow.Phoenix.PlugErrorHandler

    plug MobaWeb.OnlineHelper
  end

  pipeline :admin_protected do
    plug MobaWeb.AdminAuth
  end

  pipeline :with_hero do
    plug MobaWeb.HeroAuth
  end

  pipeline :user_helper do
    plug MobaWeb.AuthHelper
  end

  scope "/" do
    pipe_through [:browser, :user_helper]

    pow_routes()
    pow_extension_routes()

    get "/start", MobaWeb.GameController, :start
    post "/start", MobaWeb.GameController, :create
    get "/", MobaWeb.GameController, :index

    live "/battles/:id", MobaWeb.BattleLiveView, layout: {MobaWeb.LayoutView, :root}
  end

  scope "/", MobaWeb do
    pipe_through [:browser, :root_layout, :protected, :user_helper]

    live "/base", DashboardLiveView

    live "/hall", HallLiveView

    live "/about", AboutLiveView

    live "/tavern", TavernLiveView

    live "/user/:id", UserLiveView

    live "/hero/:id", HeroLiveView

    live "/library", LibraryLiveView

    live "/invoke", CreateLiveView, layout: {MobaWeb.LayoutView, :clean}

    post "/game/continue", GameController, :continue
    get "/game/:mode", GameController, :switch_mode

    live "/arena/select", ArenaSelectLiveView

    live "/duels/:id", DuelLiveView
  end

  scope "/", MobaWeb do
    pipe_through [:browser, :root_layout, :protected, :user_helper, :with_hero]

    live "/battles", BattlesLiveView

    live "/arena", ArenaLiveView

    live "/jungle", JungleLiveView

    live "/build", BuildLiveView
  end

  scope "/admin", MobaWeb do
    pipe_through [:browser, :protected, :admin_protected]

    resources "/skills", Admin.SkillController
    resources "/items", Admin.ItemController
    resources "/avatars", Admin.AvatarController
    resources "/users", Admin.UserController
    resources "/matches", Admin.MatchController
    resources "/skins", Admin.SkinController
    resources "/quests", Admin.QuestController

    live_dashboard "/dashboard", metrics: MobaWeb.Telemetry

    get "/", Admin.SkillController, :root
  end
end
