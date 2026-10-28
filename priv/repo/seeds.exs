# Fresh-install seed data, exported from canonical development records on 2026-10-27.
# Run with: mix run priv/repo/seeds.exs
# Artwork is independently generated; no development uploads are copied here.

alias Moba.{Accounts, Conductor, Game, Repo}
alias Game.Schema.{Avatar, Item, Skill, Skin}
alias Accounts.Schema.User

defmodule SeedHelper do
  @art_root Path.expand("../resources/original", __DIR__)

  def with_art(attrs, paths) do
    if System.get_env("GITHUB_ACTIONS") do
      attrs
    else
      Enum.reduce(paths, attrs, fn {field, relative_path}, attrs ->
        upload = %Plug.Upload{
          filename: Path.basename(relative_path),
          path: Path.join(@art_root, relative_path),
          content_type: "image/webp"
        }

        Map.put(attrs, field, upload)
      end)
    end
  end
end

catalog =
  __DIR__
  |> Path.join("seed_catalog.json")
  |> File.read!()
  |> Jason.decode!()

Repo.transaction(fn ->
  %User{is_admin: true, shard_count: 10000}
  |> User.changeset(%{
    email: "admin@browsermoba.com",
    username: "Admin",
    password: "123456",
    password_confirmation: "123456"
  })
  |> Repo.insert!()

  for attrs <- catalog["items"] do
    attrs = SeedHelper.with_art(attrs, [{"image", "items/#{attrs["code"]}.webp"}])
    Repo.insert!(Item.changeset(%Item{}, attrs))
  end

  skills =
    for attrs <- catalog["skills"] do
      attrs = SeedHelper.with_art(attrs, [{"image", "skills/#{attrs["code"]}.webp"}])
      Repo.insert!(Skill.changeset(%Skill{}, attrs))
    end

  for attrs <- catalog["avatars"] do
    ultimate = Enum.find(skills, &(&1.code == attrs["ultimate_code"] && &1.level == 1))

    attrs =
      SeedHelper.with_art(attrs, [
        {"image", "heroes/#{attrs["code"]}/portrait.webp"},
        {"background", "heroes/#{attrs["code"]}/default.webp"}
      ])

    Repo.insert!(Avatar.create_changeset(%Avatar{}, attrs, ultimate))
  end

  for attrs <- catalog["skins"] do
    {artwork, attrs} = Map.pop!(attrs, "artwork")
    attrs = SeedHelper.with_art(attrs, [{"background", artwork}])
    Repo.insert!(Skin.changeset(%Skin{}, attrs))
  end
end)

Conductor.regenerate_resources!()
Conductor.pvp_tick!()
Conductor.season_tick!()

(Enum.to_list(0..10) ++ Enum.to_list(17..22))
|> Conductor.regenerate_bots!()
