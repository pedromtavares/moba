defmodule Moba.ConductorTest do
  use Moba.DataCase

  describe "main game loop" do
    test "#start" do
      old = Moba.current_match()
      winner = create_pvp_hero(%{pvp_points: 10000})

      current = Conductor.start_match!(0..0)
      old = Admin.get_match!(old.id)
      winner_user = Accounts.get_user!(winner.user_id)

      assert current.active
      refute old.active
      assert current.last_server_update_at
      assert current.last_pvp_round_at

      assert Game.get_current_skill!("coup")
      assert Game.get_item_by_code!("boots_of_speed")

      assert old.winners["1"] == winner.id
      refute winner_user.current_pvp_hero_id
      refute Game.get_hero!(winner.id) |> Map.get(:pvp_active)
    end

    test "server_update!" do
      current = Moba.current_match()

      match = Conductor.server_update!(current)

      assert match.last_server_update_at > current.last_server_update_at
    end

    test "new_pvp_round!" do
      current = Moba.current_match()
      match = Conductor.new_pvp_round!(current)

      assert match.last_pvp_round_at > current.last_pvp_round_at
    end
  end
end
