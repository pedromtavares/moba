defmodule MobaWeb.RetiredRoutesTest do
  use ExUnit.Case, async: true

  alias MobaWeb.Router

  test "the retired V1 interface is no longer routed" do
    for path <- ["/v1/base", "/v1/training", "/v1/arena", "/v1/hero/1"] do
      assert Phoenix.Router.route_info(Router, "GET", path, "localhost") == :error
    end
  end

  test "unreleased prototype URLs are removed instead of redirected" do
    for path <- [
          "/draft",
          "/invoke",
          "/invoke/solo",
          "/team",
          "/team/1/matches/2",
          "/team/1/matches/2/battles/3",
          "/board",
          "/board/1",
          "/board/1/matches/2",
          "/board/1/matches/2/battles/3"
        ] do
      assert Phoenix.Router.route_info(Router, "GET", path, "localhost") == :error
    end
  end

  test "canonical game routes still use the protected V2 interface" do
    for {path, module} <- [
          {"/base", MobaWeb.V2.DashboardLive},
          {"/new", MobaWeb.V2.DraftLive},
          {"/new/solo", MobaWeb.V2.CreateLive},
          {"/training", MobaWeb.V2.TrainingLive},
          {"/battles/1", MobaWeb.V2.BattleLive},
          {"/matches/1", MobaWeb.V2.MatchLive},
          {"/arena", MobaWeb.V2.ArenaLive},
          {"/hero/1", MobaWeb.V2.HeroLive},
          {"/teams/1", MobaWeb.V2.TeamLive}
        ] do
      route = Phoenix.Router.route_info(Router, "GET", path, "localhost")
      assert elem(route.phoenix_live_view, 0) == module
      assert route.pipe_through == [:browser, :player_protected]
    end
  end

  test "creation URLs retain their path and query when normalizing old preview links" do
    for path <- ["/new", "/new?avatar=lina", "/new/solo", "/new/solo?avatar=lina"] do
      assert MobaWeb.Preview.preview_path(nil, path) == path
    end
  end
end
