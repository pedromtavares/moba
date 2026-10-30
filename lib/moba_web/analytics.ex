defmodule MobaWeb.Analytics do
  alias Moba.SiteSettings

  def measurement_id(%Plug.Conn{request_path: path, host: host}) do
    if Application.get_env(:moba, :analytics_allowed, false) &&
         host not in ["localhost", "127.0.0.1", "::1"] && !excluded_path?(path) do
      case SiteSettings.get() do
        %{analytics_enabled: true, analytics_measurement_id: "G-" <> _ = id} -> id
        _ -> nil
      end
    end
  end

  def measurement_id(_), do: nil

  defp excluded_path?(path) do
    Enum.any?(["/admin", "/dev", "/users", "/auth"], fn prefix ->
      path == prefix || String.starts_with?(path, prefix <> "/")
    end)
  end
end
