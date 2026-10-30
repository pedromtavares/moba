defmodule Moba.ReleaseTest do
  use Moba.DataCase

  alias Moba.Game.Schema.Skill

  test "resource task publishes canonical edits and leaves an existing repository running" do
    repo = Process.whereis(Repo)
    previous_uuid = Game.current_season().resource_uuid
    canonical = Repo.one!(from s in Skill, where: s.code == "decay" and s.level == 1 and is_nil(s.resource_uuid))
    canonical |> Ecto.Changeset.change(base_damage: 543) |> Repo.update!()

    Mix.Task.reenable("resources")
    on_exit(fn -> Mix.Task.reenable("resources") end)
    Mix.Task.run("resources")

    assert Process.whereis(Repo) == repo
    season = Game.current_season()
    refute season.resource_uuid == previous_uuid
    published = Game.get_current_skill!("decay", 1)
    assert published.base_damage == 543
    assert published.resource_uuid == season.resource_uuid
  end
end
