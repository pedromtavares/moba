defmodule MobaWeb.RetiredRoutesTest do
  use ExUnit.Case, async: true

  alias MobaWeb.Router

  test "the retired V1 interface is no longer routed" do
    for path <- ["/v1/base", "/v1/training", "/v1/arena", "/v1/hero/1"] do
      assert Phoenix.Router.route_info(Router, "GET", path, "localhost") == :error
    end
  end

  test "canonical game routes still use the protected V2 interface" do
    for {path, module} <- [
          {"/base", MobaWeb.V2.DashboardLive},
          {"/training", MobaWeb.V2.TrainingLive},
          {"/arena", MobaWeb.V2.ArenaLive},
          {"/hero/1", MobaWeb.V2.HeroLive}
        ] do
      route = Phoenix.Router.route_info(Router, "GET", path, "localhost")
      assert elem(route.phoenix_live_view, 0) == module
      assert route.pipe_through == [:browser, :player_protected]
    end
  end
end
