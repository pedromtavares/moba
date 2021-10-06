defmodule Mix.Tasks.Bots do
  use Mix.Task

  @shortdoc "Generates new bots"
  def run(_) do
    Mix.Task.run("app.start")
    Moba.generate_bots!()
  end
end
