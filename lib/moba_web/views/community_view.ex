defmodule MobaWeb.CommunityView do
  use MobaWeb, :view

  def formatted_body(%{body: body}) do
    body
    |> String.replace(
      ~r/https:\/\/browsermoba.com\/battles\/([0-9]+)/,
      "<a href='/battles/\\1' class='text-primary'>Battle #\\1</span>"
    )
    |> raw()
  end
end
