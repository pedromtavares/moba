defmodule Mix.Tasks.PveBots do
  use Mix.Task

  @shortdoc "Generates new PVE bots"
  def run(_) do
    Mix.Task.run("app.start")
    Moba.regenerate_pve_bots!()
  end
end
