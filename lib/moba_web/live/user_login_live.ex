defmodule MobaWeb.UserLoginLive do
  use MobaWeb, :live_view

  def render(assigns) do
    ~H"""
    <style>
      body::before {
        background-image: url(/images/home.jpg);
        background-size: cover;
        content: "";
        display: block;
        position: absolute;
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        z-index: -2;
        opacity: 0.2;
      }
    </style>
    <div class="account-pages mb-5" style="margin-top: 10rem">
      <div class="container">
        <div class="row justify-content-center">
          <div class="col-md-8 col-lg-6 col-xl-5">
            <div class="card black-bar">
              <div class="card-body pt-4 pl-4 pr-4">
                <div class="text-center w-75 m-auto">
                  <h3>Sign In to Browser MOBA</h3>
                </div>

                <%= if error = Phoenix.Flash.get(@flash, :error) do %>
                  <p class="alert alert-danger" role="alert">{error}</p>
                <% end %>

                <.form for={@form} id="login_form" action={~p"/users/log_in"} phx-update="ignore">
                  <div class="form-group">
                    <label>E-mail</label>
                    <input type="email" id={@form[:email].id} name={@form[:email].name} value={@form[:email].value} class="form-control" required />
                  </div>
                  <div class="form-group">
                    <label>Password</label>
                    <input type="password" id={@form[:password].id} name={@form[:password].name} class="form-control" required />
                  </div>
                  <div class="form-group mb-0 text-center">
                    <button class="btn btn-primary btn-block" type="submit">Sign In</button>
                  </div>
                </.form>

                <p class="text-center mt-4 mb-0">
                  <.link href={~p"/users/reset_password"} class="text-muted ml-1">Forgot your password?</.link>
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")
    {:ok, assign(socket, form: form), temporary_assigns: [form: form]}
  end
end
