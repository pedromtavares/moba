defmodule Moba.ConductorTest do
  use Moba.DataCase

  describe "main game loop" do
    test "#start" do
      old = Moba.current_match()

      current = Conductor.start_match!()
      old = Admin.get_match!(old.id)

      assert current.active
      refute old.active
      assert current.last_server_update_at

      assert Game.get_current_skill!("coup")
      assert Game.get_item_by_code!("boots_of_speed")
    end

    test "server_update!" do
      current = Moba.current_match()

      match = Conductor.server_update!(current)

      assert Date.compare(match.last_server_update_at, DateTime.utc_now()) == :eq
    end

    test "new_pvp_round!" do
      current = Moba.current_match()
      match = Conductor.new_pvp_round!(current)

      assert Date.compare(match.last_pvp_round_at, DateTime.utc_now()) == :eq
    end
  end
end
