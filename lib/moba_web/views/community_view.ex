defmodule MobaWeb.CommunityView do
  use MobaWeb, :view

  alias MobaWeb.PlayerView

  def formatted_body(%{body: body}) do
    body
    |> text_to_html()
    |> safe_to_string()
    |> String.replace(
      ~r/https:\/\/browsermoba.com\/battles\/([0-9]+)/,
      "<a href='/battles/\\1' class='text-primary'>Battle #\\1</span>"
    )
    |> raw()
  end
end
