defmodule Mix.Tasks.Restart do
  use Mix.Task

  @shortdoc "Starts a new match"
  def run(_) do
    Mix.Task.run("app.start")
    Moba.start!()
  end
end
