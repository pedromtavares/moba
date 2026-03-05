defmodule MobaWeb.V2.CreateLive do
  use MobaWeb, :v2_live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(_params, _uri, %{assigns: %{current_player: player}} = socket) do
    {:noreply, socket_player_init(player.id, socket)}
  end

  def handle_event("filter", %{"role" => role}, %{assigns: %{all_avatars: all_avatars, filter: filter}} = socket) do
    filter = if filter == role, do: nil, else: role
    avatars = if filter, do: Enum.filter(all_avatars, &(&1.role == role)), else: all_avatars
    {:noreply, assign(socket, filter: filter, avatars: avatars)}
  end

  def handle_event("pick-avatar", %{"id" => id}, %{assigns: %{cache_key: cache_key}} = socket) do
    avatar = Game.get_avatar!(id)
    put_cache(cache_key, avatar, [], nil)

    {:noreply,
     assign(socket,
       selected_avatar: avatar,
       selected_skills: [],
       selected_build_index: nil
     )
     |> set_name(avatar)}
  end

  def handle_event("repick-avatar", _, %{assigns: %{cache_key: cache_key}} = socket) do
    put_cache(cache_key, nil, [], nil)
    {:noreply, assign(socket, selected_avatar: nil, selected_skills: [], selected_build_index: nil)}
  end

  def handle_event(
        "pick-skill",
        %{"id" => id},
        %{assigns: %{custom: true, cache_key: cache_key, selected_avatar: selected_avatar} = assigns} = socket
      ) do
    skill = Game.get_skill!(id)
    selected_skills = manage_skills(assigns.selected_skills, skill)
    put_cache(cache_key, selected_avatar, selected_skills, nil)
    {:noreply, assign(socket, selected_skills: selected_skills, selected_build_index: nil)}
  end

  def handle_event("pick-skill", _, %{assigns: %{custom: false}} = socket), do: {:noreply, socket}

  def handle_event(
        "pick-build",
        %{"number" => index},
        %{assigns: %{cache_key: cache_key, selected_avatar: selected_avatar}} = socket
      ) do
    index = String.to_integer(index)
    selected_skills = selected_avatar.role |> Game.skill_build_for(index) |> elem(0)
    put_cache(cache_key, selected_avatar, selected_skills, index)
    {:noreply, assign(socket, selected_skills: selected_skills, selected_build_index: index)}
  end

  def handle_event("toggle-custom", _, %{assigns: %{custom: custom}} = socket) do
    {:noreply, assign(socket, custom: !custom)}
  end

  def handle_event("randomize", _, %{assigns: %{cache_key: cache_key, avatars: avatars}} = socket) do
    selected_avatar = avatars |> Enum.shuffle() |> List.first()
    put_cache(cache_key, selected_avatar, [], nil)
    {:noreply, assign(socket, selected_avatar: selected_avatar, selected_skills: []) |> set_name(selected_avatar)}
  end

  def handle_event(
        "create",
        _,
        %{assigns: %{current_player: player, selected_avatar: avatar, selected_skills: selected_skills, name: name}} =
          socket
      ) do
    skills = selected_skills |> Enum.map(& &1.id) |> Game.list_chosen_skills()
    hero_name = hero_name(player, avatar, name, socket)
    Game.create_current_pve_hero!(%{name: hero_name}, player, avatar, skills)
    {:noreply, socket |> redirect(to: "/training")}
  end

  def handle_event("validate", %{"name" => name}, socket) do
    {:noreply, assign(socket, error: validation_error(name, socket), name: name)}
  end

  defp add_skill(selected, skill) when length(selected) < 3, do: selected ++ [skill]
  defp add_skill(selected, _), do: selected
  defp remove_skill(selected, skill), do: selected -- [skill]

  defp get_cache(cache_key) do
    case Cachex.get(:game_cache, cache_key) do
      {:ok, nil} -> %{selected_avatar: nil, selected_skills: [], selected_build_index: nil}
      {:ok, attrs} -> attrs
    end
  end

  defp hero_name(player, _avatar, name, socket) do
    if !is_nil(name) && is_nil(validation_error(name, socket)), do: name, else: player.user.username
  end

  defp manage_skills(selected_skills, skill) do
    if Enum.member?(selected_skills, skill), do: remove_skill(selected_skills, skill), else: add_skill(selected_skills, skill)
  end

  defp put_cache(cache_key, avatar, skills, selected_build_index) do
    Cachex.put(:game_cache, cache_key, %{
      selected_avatar: avatar,
      selected_skills: skills,
      selected_build_index: selected_build_index
    })
  end

  defp set_name(%{assigns: %{current_player: %{user: %{username: username}}}} = socket, _), do: assign(socket, name: username)
  defp set_name(socket, _), do: assign(socket, name: nil)

  defp socket_init(socket) do
    assign(socket,
      custom: false,
      error: nil,
      filter: nil,
      name: nil,
      sidebar_code: "training"
    )
  end

  defp socket_player_init(player_id, %{assigns: %{current_player: player}} = socket) do
    socket = socket_init(socket)
    unlocked_codes = unlocked_codes_for(player)
    cached = get_cache(player_id)
    avatars = Game.list_creation_avatars(unlocked_codes)
    collection_codes = Enum.map(player.hero_collection, & &1["code"])
    blank_collection = Game.list_avatars() |> Enum.filter(&(&1.code not in collection_codes))
    skills = Game.list_creation_skills(1, unlocked_codes)

    assign(socket,
      all_avatars: avatars,
      avatars: avatars,
      blank_collection: blank_collection,
      cache_key: player.id,
      selected_avatar: cached.selected_avatar,
      selected_skills: cached.selected_skills,
      selected_build_index: cached.selected_build_index,
      skills: skills
    )
    |> set_name(cached.selected_avatar)
  end

  defp unlocked_codes_for(%{user: user}) when not is_nil(user), do: Accounts.unlocked_codes_for(user)
  defp unlocked_codes_for(_), do: []

  defp validation_error(name, %{assigns: %{current_player: %{user: user}}}) do
    name = String.trim(name)
    length = String.length(name)

    if length >= 3 and length <= 15 do
      if name == user.username || is_nil(Accounts.get_user_by_username(name)), do: nil, else: "Name already taken."
    else
      "Invalid name size, minimum is 3 characters."
    end
  end

  defp roles, do: MobaWeb.CreateView.roles()
  defp build_title(avatar, selected_skills, index), do: MobaWeb.CreateView.build_title(avatar, selected_skills, index)
  defp builds_for(role), do: MobaWeb.CreateView.builds_for(role)
  defp role(avatar), do: MobaWeb.CreateView.role(avatar)
  defp role_description(avatar), do: MobaWeb.CreateView.role_description(avatar)
  defp display_percentage(type, avatar, avatars), do: MobaWeb.CreateView.display_percentage(type, avatar, avatars)

  defp create_avatar_stats(assigns) do
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

  defp create_background_avatar(assigns) do
    ~H"""
    <div class={"col-xl-#{if @selected, do: 3, else: 4} col-lg-6 col-sm-12 mb-4"} id={"avatar-#{@avatar.id}"}>
      <%= if @selected do %>
        <a class="btn btn-outline-dark text-white btn-block mb-2 btn-lg" phx-click="repick-avatar" id="repick-button">
          <i class="fa fa-refresh mr-2"></i>Repick Avatar
        </a>
      <% end %>
      <div class="hero-card card">
        <div class="card-body text-center p-0" style={"background-image: url(#{GH.background_url(@avatar)})"}>
          <div class="name">
            <h3 class="m-0 text-center p-2 text-white f-rpg">{@avatar.name}</h3>
          </div>
          <%= unless @selected do %>
            <div class="ultimate p-2 tooltip-mobile" data-toggle="tooltip" title={GH.skill_description(@avatar.ultimate)}>
              <h5 class="mt-0">Ultimate</h5>
              <img src={GH.image_url(@avatar.ultimate)} style="width: 70px" class="img-border-sm" />
              <h5 class="mb-0">{@avatar.ultimate.name}</h5>
              <small><em>(mouse over for info)</em></small>
            </div>
          <% end %>
        </div>
        <div class="transparent card-footer text-center">
          <.create_avatar_stats avatar={@avatar} avatars={@avatars} />
          <%= if @selected do %>
            <div class="btn-group mt-2">
              <button class="btn btn-outline-dark text-danger">
                <i class="fa fa-heart mr-1"></i>Health <br />
                <strong>{@avatar.total_hp}</strong>
                <br />
                <small class="font-italic">{@avatar.hp_per_level} per level</small>
              </button>
              <button class="btn btn-outline-dark text-info">
                <i class="fa fa-bolt mr-1"></i>Energy <br />
                <strong>{@avatar.total_mp}</strong>
                <br />
                <small class="font-italic">{@avatar.mp_per_level} per level</small>
              </button>
              <button class="btn btn-outline-dark text-success">
                <i class="fa fa-dagger mr-1"></i>Attack <br />
                <strong>{@avatar.atk}</strong>
                <br />
                <small class="font-italic">{@avatar.atk_per_level} per level</small>
              </button>
            </div>
            <div class="btn-group mt-1">
              <button class="btn btn-outline-dark text-warning">
                <i class="fa fa-shield-halved mr-1"></i>Armor <br />
                <strong>{@avatar.armor}</strong>
              </button>
              <button class="btn btn-outline-dark text-pink">
                <i class="fa fa-galaxy mr-1"></i>Power <br />
                <strong>{@avatar.power}</strong>
              </button>
              <button class="btn btn-outline-dark text-orange">
                <i class="fa fa-running mr-1"></i>Speed <br />
                <strong>{@avatar.speed}</strong>
              </button>
            </div>
          <% end %>
          <div class="row mt-3">
            <div class="col">
              <h4 class="mt-0 d-none d-lg-block">Gameplay</h4>
              <div class="description">
                <em>{@avatar.description}</em>
              </div>
              <%= unless @selected do %>
                <a
                  href="javascript:;"
                  id={"pick-avatar-#{@avatar.id}"}
                  class="col-xl-9 col-12 margin-auto mt-2 btn btn-secondary btn-block btn-lg text-white dark-button h5"
                  phx-click="pick-avatar"
                  phx-hook="AnimateScroll"
                  phx-target-element="#create-new"
                  phx-value-id={@avatar.id}
                >
                  <img src={GH.image_url(@avatar)} class="avatar mr-2" style="max-width: 70px;white-space: nowrap;" />
                  Pick {@avatar.name}
                </a>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
