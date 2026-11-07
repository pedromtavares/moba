defmodule MobaWeb.Preview do
  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, _params, session, socket) do
    {:cont, assign(socket, :preview, session["preview"] == true)}
  end

  # The redesigned UI now uses canonical routes; normalize saved preview links too.
  def preview_path(_context, "/new"), do: "/new"
  def preview_path(_context, "/new?" <> query), do: "/new?" <> query
  def preview_path(_context, "/new/solo"), do: "/new/solo"
  def preview_path(_context, "/new/solo?" <> query), do: "/new/solo?" <> query
  def preview_path(_context, "/new/" <> path), do: "/" <> path
  def preview_path(_context, path), do: path
end
