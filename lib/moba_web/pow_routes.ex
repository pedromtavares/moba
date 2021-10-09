defmodule MobaWeb.PowRoutes do
  use Pow.Phoenix.Routes

  def after_user_updated_path(_), do: "/"
  def after_registration_path(_), do: "/game/pve"
  def after_sign_out_path(_conn), do: "/registration/new"
end
