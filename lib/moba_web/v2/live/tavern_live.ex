defmodule MobaWeb.V2.TavernLive do
  use MobaWeb, :v2_live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, index_assigns(params, socket)}
  end

  def handle_event("show-avatars", _, socket) do
    {:noreply, assign(socket, active_tab: "avatars")}
  end

  def handle_event("show-skills", _, socket) do
    {:noreply, assign(socket, active_tab: "skills")}
  end

  def handle_event("show-skins", _, socket) do
    {:noreply, assign(socket, active_tab: "skins")}
  end

  def handle_event("previous-skin", _, socket) do
    index = socket.assigns.current_index - 1
    skin = Enum.at(socket.assigns.current_skins, index)
    {:noreply, assign(socket, current_skin: skin, current_index: index)}
  end

  def handle_event("next-skin", _, socket) do
    index = socket.assigns.current_index + 1
    skin = Enum.at(socket.assigns.current_skins, index)
    {:noreply, assign(socket, current_skin: skin, current_index: index)}
  end

  def handle_event("set-avatar", %{"code" => code}, %{assigns: %{all_avatars: all_avatars}} = socket) do
    avatar = Enum.find(all_avatars, &(&1.code == code))
    skins = Game.list_avatar_skins(code)
    skin = List.first(skins)

    {:noreply, assign(socket, current_avatar: avatar, current_skins: skins, current_skin: skin, current_index: 0)}
  end

  def handle_event("set-skin", %{"code" => code}, socket) do
    skin = Enum.find(socket.assigns.current_skins, &(&1.code == code))
    {:noreply, assign(socket, current_skin: skin)}
  end

  def handle_event("unlock-avatar", %{"code" => code}, %{assigns: %{current_player: player}} = socket) do
    resource = Game.get_avatar_by_code!(code)
    {:noreply, assign(socket, current_player: create_unlock!(player, resource))}
  end

  def handle_event("unlock-skill", %{"code" => code}, %{assigns: %{current_player: player}} = socket) do
    resource = Game.get_current_skill!(code, 1)
    {:noreply, assign(socket, current_player: create_unlock!(player, resource))}
  end

  def handle_event("unlock-skin", %{"code" => code}, %{assigns: %{current_player: player}} = socket) do
    resource = Game.get_skin_by_code!(code)
    {:noreply, assign(socket, current_player: create_unlock!(player, resource))}
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
    skills = Game.list_unlockable_skills()
    current_avatar = Enum.find(all_avatars, &(&1.code == avatar_code)) || List.first(all_avatars)
    current_player = Map.put(current_player, :user, user)
    current_skins = Game.list_avatar_skins(current_avatar.code)
    current_skin = List.first(current_skins)
    featured_avatar = featured_avatar_for(current_player, avatars)

    assign(socket,
      active_tab: active_tab,
      all_avatars: all_avatars,
      avatars: avatars -- [featured_avatar],
      avatar_code: avatar_code,
      current_avatar: current_avatar,
      current_index: 0,
      current_player: current_player,
      current_skins: current_skins,
      current_skin: current_skin,
      featured_avatar: featured_avatar,
      sidebar_code: "tavern",
      skills: skills
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

  defp role(avatar), do: MobaWeb.CreateView.role(avatar)
  defp role_description(avatar), do: MobaWeb.CreateView.role_description(avatar)
  defp display_percentage(type, avatar, avatars), do: MobaWeb.CreateView.display_percentage(type, avatar, avatars)

  defp tavern_unlock_actions(assigns) do
    ~H"""
    <div class="text-center my-2">
      <%= if can_unlock?(@resource, @player) do %>
        <a
          href="javascript:;"
          class="btn btn-outline-warning btn-lg"
          phx-click={@action}
          phx-value-code={@resource.code}
          phx-hook="Loading"
          id={"unlock-#{@resource.code}"}
        >
          <span class="loading-text">
            <i class="fab fa-ethereum mr-1"></i>Unlock for {price_to_unlock(@resource)} Shards
          </span>
        </a>
      <% else %>
        <a href="javascript:;" class="btn btn-secondary no-action">
          <i class="fa fa-lock mr-1"></i>{unlock_error_message(@resource, @player)}
        </a>
      <% end %>
    </div>
    """
  end

  defp tavern_avatar_stats(assigns) do
    ~H"""
    <div class="row align-items-center">
      <div class="col text-center font-weight-bold border-bottom">
        <h4 class="m-0">
          <img src={"/images/#{@avatar.role}_icon.png"} style="width: 30px" class="text-center mr-1" />{role(@avatar)}
          <br />
          <small class="font-italic d-block mb-2 mt-1">
            {role_description(@avatar)}
          </small>
        </h4>
      </div>
    </div>
    <div class="row align-items-center">
      <div class="col-6 text-right border-bottom border-right text-danger font-weight-bold stat-col">
        <i class="fa fa-dagger mr-1"></i>Offense
      </div>
      <div class="col">
        <div class="progress progress-fixed">
          <div style={"width:#{display_percentage(:offense, @avatar, @avatars)}%"} class="progress-bar bg-danger">
            <span></span>
          </div>
        </div>
      </div>
    </div>
    <div class="row align-items-center">
      <div class="col-6 text-right border-bottom border-right text-warning font-weight-bold stat-col">
        <i class="fa fa-shield-halved mr-1"></i>Defense
      </div>
      <div class="col">
        <div class="progress progress-fixed">
          <div style={"width:#{display_percentage(:defense, @avatar, @avatars)}%"} class="progress-bar bg-warning">
            <span></span>
          </div>
        </div>
      </div>
    </div>
    <div class="row align-items-center">
      <div class="col-6 text-right border-bottom border-right text-primary font-weight-bold stat-col">
        <i class="fa fa-magic mr-1"></i>Magic
      </div>
      <div class="col">
        <div class="progress progress-fixed">
          <div style={"width:#{display_percentage(:magic, @avatar, @avatars)}%"} class="progress-bar bg-primary">
            <span></span>
          </div>
        </div>
      </div>
    </div>
    <div class="row align-items-center">
      <div class="col-6 text-right border-bottom border-right text-success font-weight-bold stat-col">
        <i class="fa fa-running mr-1"></i>Speed
      </div>
      <div class="col">
        <div class="progress progress-fixed">
          <div style={"width:#{display_percentage(:speed, @avatar, @avatars)}%"} class="progress-bar bg-success">
            <span></span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp tavern_avatar_card(assigns) do
    assigns = assign_new(assigns, :featured, fn -> false end)

    ~H"""
    <div class="col-xl-4 col-lg-6 col-sm-12 mb-2" id={"avatar-#{@avatar.id}"}>
      <div class="hero-card card ribbon-box">
        <%= if @featured do %>
          <div class="ribbon-two ribbon-two-purple"><span>Free</span></div>
        <% else %>
          <%= if unlocked?(@avatar, @player) do %>
            <div class="ribbon-two ribbon-two-secondary"><span>Unlocked</span></div>
          <% end %>
        <% end %>
        <div class="card-body text-center p-0" style={"background-image: url(#{GH.background_url(@avatar)})"}>
          <div class="name">
            <h3 class="m-0 text-center p-2 text-white f-rpg">{@avatar.name}</h3>
          </div>
          <div class="ultimate" data-toggle="tooltip" title={GH.skill_description(@avatar.ultimate)}>
            <h4 class="mt-0">Ultimate</h4>
            <img src={GH.image_url(@avatar.ultimate)} style="width: 70px" class="img-border-sm" />
            <h5 class="mb-0">{@avatar.ultimate.name}</h5>
            <small><em>(mouse over for info)</em></small>
          </div>
        </div>

        <div class="transparent card-footer text-center">
          <.tavern_avatar_stats avatar={@avatar} avatars={@avatars} />
          <div class="row mt-3">
            <div class="col">
              <h4 class="mt-0 d-none d-lg-block">Gameplay</h4>
              <div class="description">
                <em>{@avatar.description}</em>
              </div>
              <%= if @featured do %>
                <div class="text-center my-2">
                  <a href="/auth?origin=tavern" class="btn btn-purple btn-lg btn-block">
                    <i class="fab fa-discord"></i> Connect with Discord to Unlock
                  </a>
                </div>
              <% else %>
                <%= unless unlocked?(@avatar, @player) do %>
                  <.tavern_unlock_actions resource={@avatar} player={@player} action="unlock-avatar" />
                <% end %>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp tavern_skill_card(assigns) do
    ~H"""
    <div class="col-12 col-md-6 col-lg-4 col-xl-3" id={"skill-#{@skill.id}"}>
      <div class="card ribbon-box">
        <%= if unlocked?(@skill, @player) do %>
          <div class="ribbon-two ribbon-two-secondary"><span>Unlocked</span></div>
        <% end %>
        <div class="card-body text-center">
          <img
            src={GH.image_url(@skill)}
            class={["skill-img img-border", @skill.passive && "passive"]}
            data-toggle="tooltip"
            title={GH.skill_description(@skill)}
          />
          <br />
          <h3 class="f-rpg">
            {@skill.name}<br />
            <small class="font-italic text-muted">(mouse over image for info)</small>
          </h3>
        </div>
        <%= unless unlocked?(@skill, @player) do %>
          <.tavern_unlock_actions resource={@skill} player={@player} action="unlock-skill" />
        <% end %>
      </div>
    </div>
    """
  end
end
