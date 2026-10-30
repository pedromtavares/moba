# Read-only checks for a freshly seeded installation.
# Run from the repository root with: mix run priv/repo/check_setup.exs

alias Moba.{Game, Repo}
alias Moba.Accounts.Schema.User
alias Moba.Game.Schema.{Avatar, Hero, Item, Skill, Skin}
import Ecto.Query

check! = fn condition, message ->
  unless condition, do: Mix.raise(message)
end

catalog = __DIR__ |> Path.join("seed_catalog.json") |> File.read!() |> Jason.decode!()
admin = Repo.get_by(User, email: "admin@browsermoba.com")
check!.(admin && admin.is_admin, "Missing seeded admin: admin@browsermoba.com")
check!.(User.valid_password?(admin, "123456"), "Seeded admin password does not match README")
IO.puts("OK: seeded admin authenticates and has admin permissions")

season = Game.current_season()
check!.(season && season.resource_uuid, "Missing active season or published resource UUID")

for {schema, key} <- [{Avatar, "avatars"}, {Item, "items"}, {Skill, "skills"}] do
  canonical = Repo.all(from r in schema, where: is_nil(r.resource_uuid))
  current = Repo.all(from r in schema, where: r.current == true)
  identity = fn row -> {row.code, Map.get(row, :level)} end
  expected = Enum.map(catalog[key], &{&1["code"], &1["level"]}) |> Enum.sort()
  expected_current = Enum.filter(canonical, & &1.enabled) |> Enum.map(identity) |> Enum.sort()

  check!.(Enum.sort(Enum.map(canonical, identity)) == expected, "Incomplete canonical #{key}")
  check!.(Enum.sort(Enum.map(current, identity)) == expected_current, "Incomplete published #{key}")
  check!.(Enum.all?(current, &(&1.resource_uuid == season.resource_uuid)), "Stale published #{key}")
  IO.puts("OK: #{length(canonical)} canonical / #{length(current)} published #{key}")
end

skins = Repo.all(Skin)

check!.(
  Enum.sort(Enum.map(skins, & &1.code)) == Enum.sort(Enum.map(catalog["skins"], & &1["code"])),
  "Incomplete skins"
)

IO.puts("OK: #{length(skins)} Master and Grandmaster skins")

for tier <- 0..(Moba.master_league_tier() - 1),
    step <- 0..(Game.max_league_step_for(tier) - 1) do
  defender = Game.Leagues.league_defender_for(%{id: -1, league_tier: tier, league_step: step})
  check!.(defender, "Missing league opponent for tier #{tier}, step #{step}")
end

for difficulty <- ["pvp_master", "pvp_grandmaster"] do
  count = Repo.aggregate(from(h in Hero, where: h.bot_difficulty == ^difficulty and is_nil(h.archived_at)), :count)
  check!.(count >= 5, "Missing #{difficulty} fallback opponents")
end

check!.(Game.Avatars.boss!(), "Missing boss avatar")
check!.(Enum.all?(Game.Skills.boss!()), "Missing boss skills")
IO.puts("OK: all league steps, boss resources, and PvP fallback opponents")

unless System.get_env("GITHUB_ACTIONS") do
  for {schema, fields} <- [{Avatar, [:image, :background]}, {Item, [:image]}, {Skill, [:image]}, {Skin, [:background]}],
      record <- Repo.all(schema),
      field <- fields do
    attachment = Map.fetch!(record, field)
    check!.(attachment, "Missing #{field} attachment for #{record.code}")
    uploader = if field == :background, do: Moba.Background, else: Moba.Image
    path = uploader.url({attachment, record}) |> URI.parse() |> Map.fetch!(:path) |> String.trim_leading("/")
    check!.(File.regular?(path), "Missing local artwork: #{path}")
  end

  IO.puts("OK: all seeded artwork exists in local upload storage")
end

for path <- [
      "priv/static/css/app.css",
      "priv/static/js/app.js"
    ] do
  check!.(File.regular?(path), "Missing asset bundle: #{path}; follow the README asset build steps")
end

IO.puts("OK: Webpack asset bundles exist")
IO.puts("Installation checks passed. Start with mix phx.server; sign in at /users/log_in, then open /admin.")
