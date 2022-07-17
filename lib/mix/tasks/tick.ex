defmodule Mix.Tasks.Tick do
  use Mix.Task

  @shortdoc "Season tick"
  def run(_) do
    Mix.Task.run("app.start")
    Moba.Conductor.season_tick!()
  end
end
