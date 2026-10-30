defmodule MobaWeb.V2.RasterIconsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias MobaWeb.CoreComponents

  @root Path.expand("../../..", __DIR__)

  test "game symbols render local raster icon classes" do
    for {name, symbol} <- [
          {"health", "heart"},
          {"energy", "bolt"},
          {"attack", "dagger"},
          {"armor", "shield"},
          {"power", "vortex"},
          {"speed", "runner"},
          {"offense", "fist"},
          {"magic", "wand"},
          {"battle-log", "list"},
          {"refresh", "refresh"},
          {"back", "arrow-left"},
          {"clock", "clock"},
          {"trophy", "trophy"}
        ] do
      document = render_component(&CoreComponents.icon/1, name: "game-#{name}") |> LazyHTML.from_fragment()
      assert LazyHTML.attribute(LazyHTML.query(document, ".ui-icon.ui-#{symbol}"), "aria-hidden") == ["true"]
    end
  end

  test "every raster mask ships a transparent PNG at a stable local path" do
    css = File.read!(Path.join(@root, "assets/css/ui_icons.scss"))
    paths = Regex.scan(~r{url\("(/images/ui/[^\"]+\.png)"\)}, css, capture: :all_but_first) |> List.flatten()
    assert length(paths) > 70

    for path <- paths do
      png = File.read!(Path.join(@root, "assets/static" <> path))
      assert <<137, "PNG", 13, 10, 26, 10, _::binary>> = png
      assert <<_::binary-size(16), 128::32, 128::32, 8, 6, _::binary>> = png
    end
  end

  test "runtime templates, styles and hooks have no Font Awesome dependency" do
    manifest = File.read!(Path.join(@root, "assets/static/images/ui/manifest.json")) |> Jason.decode!()
    symbols = Map.keys(manifest["icons"]) ++ ["icon", "spin", "2x", "3x"]

    files =
      Path.wildcard(Path.join(@root, "lib/**/*.{ex,heex,eex}")) ++
        Path.wildcard(Path.join(@root, "assets/css/**/*.{scss,css}")) ++
        Path.wildcard(Path.join(@root, "assets/js/**/*.js"))

    for file <- files do
      source = File.read!(file)
      refute source =~ ~r{fontawesome|font-awesome|Font Awesome|\bfa-[\w-]+}, file

      unless Path.extname(file) in [".scss", ".css"] do
        for [_, symbol] <- Regex.scan(~r/\bui-([a-z0-9-]+)/, source) do
          assert symbol in symbols, "Unmapped raster icon #{symbol} in #{file}"
        end
      end
    end
  end
end
