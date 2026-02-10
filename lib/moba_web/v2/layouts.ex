defmodule MobaWeb.V2.Layouts do
  use Phoenix.Component

  import Phoenix.Controller, only: [get_csrf_token: 0]

  use Phoenix.VerifiedRoutes,
    endpoint: MobaWeb.Endpoint,
    router: MobaWeb.Router,
    statics: MobaWeb.static_paths()

  embed_templates "layouts/*"
end
