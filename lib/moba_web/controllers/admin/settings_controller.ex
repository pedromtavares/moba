defmodule MobaWeb.Admin.SettingsController do
  use MobaWeb, :controller

  alias Moba.SiteSettings
  import Phoenix.Component, only: [to_form: 2]

  plug :put_layout, html: {MobaWeb.LayoutView, :torch}

  def edit(conn, _params) do
    render(conn, :edit, form: to_form(SiteSettings.change(), as: :settings))
  end

  def update(conn, %{"settings" => params}) do
    case SiteSettings.update(conn.assigns.current_user, params) do
      {:ok, _settings} ->
        conn |> put_flash(:info, "Site settings saved.") |> redirect(to: ~p"/admin/settings")

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> render(:edit, form: to_form(changeset, as: :settings))
    end
  end
end
