defmodule MobaWeb.UserLive do
  use MobaWeb, :live_view

  def mount(_, _session, socket) do
    {:ok, socket}
  end

  def handle_params(%{"id" => id}, _uri, socket) do
    with socket = user_assigns(id, socket) do
      if connected?(socket), do: MobaWeb.subscribe("user-ranking")
      {:noreply, socket}
    end
  end

  def handle_event("set-featured", %{"id" => id}, socket) do
    with featured = Game.get_hero!(id) do
      {:noreply, assign(socket, featured: featured)}
    end
  end

  def handle_info({"ranking", _}, %{assigns: %{user: %{id: id}}} = socket) do
    with user = Accounts.get_user!(id),
         ranking = Accounts.search(user) do
      {:noreply, assign(socket, ranking: ranking, user: user)}
    end
  end

  def render(assigns) do
    MobaWeb.UserView.render("show.html", assigns)
  end

  defp featured_hero(%{hero_collection: collection}) when length(collection) > 0 do
    hero = List.first(collection)
    Game.get_hero!(hero["hero_id"])
  end

  defp featured_hero(user), do: Game.current_pve_hero(user)

  defp user_assigns(user_id, %{assigns: %{current_user: current_user}} = socket) do
    with user = Accounts.get_user_with_current_heroes!(user_id),
         collection_codes = Enum.map(user.hero_collection, & &1["code"]),
         blank_collection = Game.list_avatars() |> Enum.filter(&(&1.code not in collection_codes)),
         duels = Game.list_finished_duels(user),
         featured = featured_hero(user),
         ranking = Accounts.search(user),
         sidebar_code = if(user.id == current_user.id, do: "user", else: nil) do
      assign(socket,
        blank_collection: blank_collection,
        duels: duels,
        featured: featured,
        ranking: ranking,
        sidebar_code: sidebar_code,
        user: user
      )
    end
  end
end
