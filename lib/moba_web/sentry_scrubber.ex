defmodule MobaWeb.SentryScrubber do
  def body(%Plug.Conn{request_path: path}) when path in ["/return", "/return/check"], do: %{}
  def body(conn), do: Sentry.PlugContext.default_body_scrubber(conn)
end
