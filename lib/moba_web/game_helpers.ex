defmodule MobaWeb.GameHelpers do
  @moduledoc """
  Global utilities used by templates and views throughout the app
  """

  def image_url(%{"code" => "basic_attack"}), do: "/images/basic_attack.png"
  def image_url(%{code: "basic_attack"}), do: "/images/basic_attack.png"
  def image_url(%{code: "disarmed"}), do: "/images/disarmed.png"
  def image_url(%{code: "invulnerable"}), do: "/images/invulnerable.png"
  def image_url(%{code: "evade"}), do: "/images/evade.png"
  def image_url(%{image: image} = resource), do: get_url(image, resource)
  def image_url(%{"image" => image} = resource), do: get_url(image, resource)

  def background_url(%{skin: %{background: background} = skin}), do: get_background_url(background, skin)
  def background_url(%{avatar: %{background: background} = avatar}), do: get_background_url(background, avatar)
  def background_url(%{background: background} = resource), do: get_background_url(background, resource)
  def background_url(%{"background" => background} = resource), do: get_background_url(background, resource)

  # image field needs to be converted to a map of atoms due to serialization
  defp get_url(image, resource) do
    image =
      if image && Map.get(image, "file_name") do
        for {key, val} <- image, into: %{}, do: {String.to_atom(key), val}
      else
        image
      end

    Moba.Image.url({image, resource}, :original)
  end

  # image field needs to be converted to a map of atoms due to serialization
  defp get_background_url(background, resource) do
    background =
      if background && Map.get(background, "file_name") do
        for {key, val} <- background, into: %{}, do: {String.to_atom(key), val}
      else
        background
      end

    Moba.Background.url({background, resource}, :original)
  end
end
