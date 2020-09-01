defmodule Mix.Tasks.Skynet do
  use Mix.Task

  @shortdoc "Server update with skynet attack"
  def run(_) do
    Mix.Task.run("app.start")
    Moba.Game.server_update!()
  end
end
