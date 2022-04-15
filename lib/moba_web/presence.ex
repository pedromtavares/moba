defmodule MobaWeb.Presence do
  use Phoenix.Presence,
    otp_app: :moba,
    pubsub_server: Moba.PubSub
end
