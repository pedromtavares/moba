defmodule Mix.Tasks.PvpBots do
  use Mix.Task

  @shortdoc "Generates new PVP bots"
  def run(_) do
    Mix.Task.run("app.start")
    Moba.regenerate_pvp_bots!()
  end
end
