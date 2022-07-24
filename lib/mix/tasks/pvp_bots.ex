defmodule Mix.Tasks.PvpBots do
  use Mix.Task

  @shortdoc "Generates new PVP bots"
  def run(_) do
    Mix.Task.run("app.start")
    Moba.Conductor.regenerate_pvp_bots!()
  end
end
