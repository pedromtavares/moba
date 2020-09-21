defmodule Mix.Tasks.Cleanup do
  use Mix.Task

  @shortdoc "Deletes old battles and heroes"
  def run(_) do
    Mix.Task.run("app.start")

    Moba.cleanup()
  end
end
