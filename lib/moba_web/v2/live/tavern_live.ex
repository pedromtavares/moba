defmodule MobaWeb.V2.TavernLive do
  use MobaWeb, :v2_live_view

  import MobaWeb.CoreComponents, only: [icon: 1]

  def mount(_params, _session, socket) do
    socket = assign_new(socket, :current_scope, fn -> Game.TeamRuns.scope(socket.assigns.current_player) end)
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, index_assigns(params, socket)}
  end

  def handle_event("show-avatars", _, socket) do
    {:noreply, assign(socket, active_tab: "avatars")}
  end

  def handle_event("show-skins", _, socket) do
    {:noreply, assign(socket, active_tab: "skins")}
  end

  def handle_event("browse-avatar", %{"code" => code}, socket) do
    avatar = Enum.find(socket.assigns.avatars, &(&1.code == code))
    {:noreply, if(avatar, do: assign(socket, selected_avatar: avatar), else: socket)}
  end

  def handle_event(event, _, socket) when event in ["previous-skin", "next-skin"] do
    step = if event == "next-skin", do: 1, else: -1
    index = socket.assigns.current_index + step
    skin = if index >= 0, do: Enum.at(socket.assigns.current_skins, index)
    {:noreply, if(skin, do: assign(socket, current_skin: skin, current_index: index), else: socket)}
  end

  def handle_event("set-avatar", %{"code" => code}, socket) do
    case Enum.find(socket.assigns.all_avatars, &(&1.code == code)) do
      nil ->
        {:noreply, socket}

      avatar ->
        skins = Game.list_avatar_skins(code)

        {:noreply,
         assign(socket, current_avatar: avatar, current_skins: skins, current_skin: List.first(skins), current_index: 0)}
    end
  end

  def handle_event("unlock-avatar", %{"code" => code}, %{assigns: %{current_player: player}} = socket) do
    resource = Game.get_avatar_by_code!(code)
    player = create_unlock!(player, resource)
    socket = assign(socket, current_player: player)

    socket =
      if socket.assigns.preview && unlocked?(resource, player),
        do: put_flash(socket, :info, "#{resource.name} unlocked. It's now in your collection."),
        else: socket

    {:noreply, socket}
  end

  def handle_event("unlock-skin", %{"code" => code}, %{assigns: %{current_player: player}} = socket) do
    resource = Game.get_skin_by_code!(code)
    player = create_unlock!(player, resource)
    socket = assign(socket, current_player: player)

    socket =
      if socket.assigns.preview && unlocked?(resource, player),
        do: put_flash(socket, :info, "#{resource.name} unlocked. It's now in your collection."),
        else: socket

    {:noreply, socket}
  end

  defp create_unlock!(%{user: user} = player, resource) do
    user = Accounts.buy_unlock!(user, resource)
    Map.put(player, :user, user)
  end

  defp featured_avatar_for(player, avatars) do
    not unlocked?(%{code: "tinker"}, player) && Enum.find(avatars, &(&1.code == "tinker"))
  end

  defp index_assigns(params, %{assigns: %{current_player: current_player}} = socket) do
    avatar_code = Map.get(params, "avatar")
    active_tab = if avatar_code, do: "skins", else: "avatars"
    avatars = Game.list_unlockable_avatars()
    all_avatars = Game.list_avatars() |> Enum.sort_by(& &1.level_requirement, :desc)
    user = Accounts.get_user_with_unlocks!(current_player.user_id)
    current_avatar = Enum.find(all_avatars, &(&1.code == avatar_code)) || List.first(all_avatars)
    current_player = Map.put(current_player, :user, user)
    current_skins = if current_avatar, do: Game.list_avatar_skins(current_avatar.code), else: []
    current_skin = List.first(current_skins)
    featured_avatar = featured_avatar_for(current_player, avatars)
    avatars = if featured_avatar, do: [featured_avatar | List.delete(avatars, featured_avatar)], else: avatars

    assign(socket,
      active_tab: active_tab,
      all_avatars: all_avatars,
      avatars: avatars,
      selected_avatar: List.first(avatars),
      current_avatar: current_avatar,
      current_index: 0,
      current_player: current_player,
      current_skins: current_skins,
      current_skin: current_skin,
      featured_avatar: featured_avatar,
      sidebar_code: "tavern"
    )
  end

  defp unlocked?(resource, %{user: user}) do
    user.unlocks
    |> Enum.map(fn unlock -> unlock.resource_code end)
    |> Enum.member?(resource.code)
  end

  defp can_unlock?(%Game.Schema.Skin{league_tier: league_tier, avatar_code: avatar_code} = resource, player) do
    has_hero_in_collection?(avatar_code, league_tier, player) && has_enough_shards?(resource, player)
  end

  defp can_unlock?(resource, player), do: has_enough_shards?(resource, player)

  defp unlock_error_message(%Game.Schema.Skin{league_tier: league_tier, avatar_code: avatar_code} = resource, player) do
    if has_enough_shards?(resource, player) do
      league = Moba.leagues()[league_tier]
      avatar = Game.get_avatar_by_code!(avatar_code)
      "You need to have #{avatar.name} in the #{league} to unlock this Skin"
    else
      price_error_message(resource, player)
    end
  end

  defp unlock_error_message(resource, player), do: price_error_message(resource, player)

  defp price_to_unlock(resource), do: Accounts.price_to_unlock(resource)

  defp has_hero_in_collection?(avatar_code, league_tier, %{hero_collection: collection}) do
    Enum.find(collection, fn %{"code" => code, "tier" => tier} ->
      avatar_code == code && tier >= league_tier
    end)
  end

  defp has_enough_shards?(resource, %{user: user}), do: user.shard_count >= price_to_unlock(resource)

  defp price_error_message(resource, %{user: user}) do
    price = price_to_unlock(resource)
    "Not enough Shards to unlock (#{user.shard_count}/#{price})"
  end

  defp role(%{role: role}) when not is_nil(role), do: String.capitalize(role)
  defp role(_), do: ""

  defp role_description(%{role: role}) do
    case role do
      "tank" -> "High defense for sustained damage absorption."
      "bruiser" -> "Tankier than most, good offense."
      "nuker" -> "Obliterate opponents with constant spellcasting."
      "carry" -> "Swift destruction."
      "support" -> "Tactical spellcasting for elegant victories."
      _ -> ""
    end
  end

  defp display_percentage(:offense, avatar, avatars) do
    max = Enum.max_by(avatars, fn avatar -> avatar.display_offense end)
    avatar.display_offense * 100 / max.display_offense
  end

  defp display_percentage(:defense, avatar, avatars) do
    max = Enum.max_by(avatars, fn avatar -> avatar.display_defense end)
    avatar.display_defense * 100 / max.display_defense
  end

  defp display_percentage(:magic, avatar, avatars) do
    max = Enum.max_by(avatars, fn avatar -> avatar.display_magic end)
    avatar.display_magic * 100 / max.display_magic
  end

  defp display_percentage(:speed, avatar, avatars) do
    max = Enum.max_by(avatars, fn avatar -> avatar.display_speed end)
    avatar.display_speed * 100 / max.display_speed
  end

  defp tavern_unlock_actions(assigns) do
    ~H"""
    <div class="tavern-unlock" data-available={to_string(!!can_unlock?(@resource, @player))}>
      <%= if can_unlock?(@resource, @player) do %>
        <button
          type="button"
          class="btn tavern-unlock-button"
          phx-click={@action}
          phx-value-code={@resource.code}
          phx-disable-with="Unlocking…"
          id={"unlock-#{@resource.code}"}
        >
          <span>Unlock</span>
          <span class="tavern-unlock-cost">◆ {price_to_unlock(@resource)} <small>Shards</small></span>
        </button>
      <% else %>
        <button type="button" class="btn tavern-unlock-button" disabled>
          <span>Locked</span>
          <span class="tavern-unlock-cost">◆ {price_to_unlock(@resource)} <small>Shards</small></span>
        </button>
        <p class="tavern-unlock-requirement">
          <%= if has_enough_shards?(@resource, @player) do %>
            {unlock_error_message(@resource, @player)}
          <% else %>
            {price_to_unlock(@resource) - @player.user.shard_count} more Shards needed
          <% end %>
        </p>
      <% end %>
    </div>
    """
  end

  defp tavern_roster(assigns) do
    ~H"""
    <div :if={@avatars != []} class="tavern-roster">
      <div class="manual-avatar-grid" role="group" aria-label="Choose an avatar">
        <button
          :for={avatar <- @avatars}
          id={"#{@event}-#{avatar.code}"}
          type="button"
          phx-click={@event}
          phx-value-code={avatar.code}
          aria-pressed={to_string(@selected && @selected.id == avatar.id)}
          title={avatar.name}
        >
          <img src={GH.image_url(avatar)} alt="" />
          <span>{avatar.name}</span>
        </button>
      </div>
    </div>
    """
  end

  defp tavern_avatar_card(assigns) do
    ~H"""
    <div class="tavern-avatar-stage" id={"avatar-#{@avatar.id}"} style={"--avatar-art: url(#{GH.background_url(@avatar)})"}>
      <div class="tavern-avatar-identity">
        <p class="tavern-avatar-role">
          <img src={"/images/#{@avatar.role}_icon.png"} alt="" /> {role(@avatar)}
        </p>
        <h2>{@avatar.name}</h2>
        <p>{@avatar.description}</p>
      </div>
      <div class="tavern-catalog-readout">
        <div
          :if={@avatar.ultimate}
          class="tavern-avatar-ultimate"
          tabindex="0"
          data-toggle="tooltip"
          title={TT.skill_tooltip(@avatar.ultimate)}
        >
          <img src={GH.image_url(@avatar.ultimate)} alt="" />
          <div><small>Ultimate</small><strong>{@avatar.ultimate.name}</strong></div>
        </div>
        <div class="tavern-avatar-attributes" aria-label={role_description(@avatar)}>
          <div
            :for={
              {stat, label, icon} <- [
                {:offense, "Offense", "game-offense"},
                {:defense, "Defense", "game-defense"},
                {:magic, "Magic", "game-magic"},
                {:speed, "Speed", "game-speed"}
              ]
            }
            class="tavern-avatar-attribute"
            data-stat={stat}
          >
            <span><.icon name={icon} />{label}</span>
            <progress value={display_percentage(stat, @avatar, @avatars)} max="100" aria-label={label}></progress>
          </div>
        </div>
        <%= cond do %>
          <% @featured -> %>
            <div>
              <a id="tavern-discord-unlock" href="/auth?origin=tavern" class="tavern-discord-unlock">
                <i class="ui-icon ui-chat-controller" aria-hidden="true"></i>
                <span>Unlock with Discord</span><span aria-hidden="true">↗</span>
              </a>
              <p class="tavern-discord-note">Free avatar · Connect your Discord account</p>
            </div>
          <% unlocked?(@avatar, @player) -> %>
            <div class="tavern-owned"><i class="ui-icon ui-unlock" aria-hidden="true"></i> Unlocked</div>
          <% true -> %>
            <.tavern_unlock_actions resource={@avatar} player={@player} action="unlock-avatar" />
        <% end %>
      </div>
    </div>
    """
  end
end
