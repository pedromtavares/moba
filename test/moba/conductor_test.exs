defmodule Moba.ConductorTest do
  use Moba.DataCase

  describe "main game loop" do
    test "season_tick!" do
      current = Moba.current_season()

      season = Conductor.season_tick!(current)

      assert Date.compare(season.last_server_update_at, DateTime.utc_now()) == :eq
    end
  end
end
