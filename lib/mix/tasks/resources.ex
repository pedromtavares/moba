defmodule Mix.Tasks.Resources do
  use Mix.Task

  @shortdoc "Regenerates resources from canon"
  def run(_) do
    Mix.Task.run("app.start")
    Moba.Conductor.regenerate_resources!()
  end
end
