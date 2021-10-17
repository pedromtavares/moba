defmodule MobaWeb.ChatView do
  use MobaWeb, :view

  def chat_message(body) do
    body
    |> String.replace(
      ~r/https:\/\/browsermoba.com\/battles\/([0-9]+)/,
      "<a href='/battles/\\1' class='text-primary'>Battle #\\1</span>"
    )
    |> raw()
  end

  def message_alerts(alerts), do: alerts |> Enum.filter(fn alert -> alert.type == "message" end)
end
