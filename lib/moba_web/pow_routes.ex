defmodule MobaWeb.PowRoutes do
  use Pow.Phoenix.Routes

  def after_user_updated_path(_), do: "/"
  def after_registration_path(_), do: "/training"
end
