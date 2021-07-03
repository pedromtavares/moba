defmodule Mix.Tasks.ResetBotRanks do
  use Mix.Task

  import Ecto.Query, only: [from: 2]

  @shortdoc "Resets season points for bots"
  def run(_) do
    Mix.Task.run("app.start")
    query = from(user in Moba.Accounts.Schema.User, where: user.is_bot == true)
    query |> Moba.Repo.update_all(set: [season_points: 0, season_tier: 0])
  end
end
