defmodule MobaWeb.V2.Components.CreateComponents do
  use Phoenix.Component

  import MobaWeb.V2.Components.GameComponents, only: [league_badge: 1]

  alias Moba.Game
  alias MobaWeb.V2.Components.GameHelpers, as: GH

  attr :avatars, :list, required: true
  attr :all_avatars, :list, required: true
  attr :blank_collection, :list, default: []
  attr :current_player, :map, required: true
  attr :filter, :string, default: nil

  def avatar_picker(assigns) do
    ~H"""
    <%= if @current_player && length(@current_player.hero_collection) > 0 do %>
      <div class="row mt-3">
        <div class="col">
          <div class="card-box collection p-2">
            <div class="row">
              <div class="col">
                <h3 class="text-center mt-1 mb-2">Your Collection</h3>
              </div>
            </div>
            <%= for hero <- @current_player.hero_collection do %>
              <div
                style="width: 100px;"
                class="avatar-container text-center mx-1"
                data-toggle="tooltip"
                title={hero["avatar"]["name"]}
            >
              <img src={GH.image_url(hero["avatar"])} class="avatar" />
              <.league_badge tier={hero["tier"]} variant="legacy" />
            </div>
            <% end %>
            <%= for avatar <- @blank_collection do %>
              <div style="width:100px;height:75px" class="avatar-container text-center mx-1">
                <img src={GH.image_url(avatar)} class="avatar blank-avatar" data-toggle="tooltip" title={avatar.name} />
              </div>
            <% end %>
          </div>
        </div>
      </div>
    <% end %>

    <div class="row mt-2 mb-3">
      <div class="col text-center">
        <h1>
          Pick your
          <%= if @filter do %>
            <span class="text-danger">{String.capitalize(@filter)}</span>
          <% end %>Avatar<br /><small><em>You can filter by Role below</em></small>
        </h1>
        <%= for role <- roles() do %>
          <a
            href="#"
            class={"btn btn-outline-dark text-white m-1 #{if @filter == role, do: "active"}"}
            phx-click="filter"
            phx-value-role={role}
          >
            <img src={"/images/#{role}_icon.png"} style="width: 30px" class="text-center mr-1" />{String.capitalize(role)}
          </a>
        <% end %>
        <a class="btn btn-outline-dark text-white m-1" phx-click="randomize" id="randomize-button">
          <i class="fa fa-dice mr-2" style="font-size: 1.3rem"></i>Randomize
        </a>
      </div>
    </div>

    <div class="row text-center">
      <.background_avatar
        :for={avatar <- @avatars |> Enum.uniq() |> Enum.sort_by(& &1.name)}
        avatar={avatar}
        avatars={@all_avatars}
        selected={false}
      />
    </div>
    """
  end

  attr :all_avatars, :list, required: true
  attr :current_player, :map, required: true
  attr :custom, :boolean, required: true
  attr :error, :string, default: nil
  attr :name, :string, default: nil
  attr :selected_avatar, :map, required: true
  attr :selected_build_index, :integer, default: nil
  attr :selected_skills, :list, required: true
  attr :skills, :list, required: true

  def selected_avatar_panel(assigns) do
    ~H"""
    <div class="row mt-3" phx-hook="ScrollToTop" id="scroll-to-top">
      <.background_avatar avatar={@selected_avatar} avatars={@all_avatars} selected={true} />

      <div class="col">
        <div class="card-box dark-bg">
          <%= if @custom do %>
            <.custom_skill_picker skills={@skills} selected_skills={@selected_skills} />
          <% else %>
            <.build_picker
              role={@selected_avatar.role}
              selected_build_index={@selected_build_index}
            />
          <% end %>

          <.selected_skills_bar
            custom={@custom}
            selected_avatar={@selected_avatar}
            selected_build_index={@selected_build_index}
            selected_skills={@selected_skills}
          />

          <.create_submit_panel
            current_player={@current_player}
            custom={@custom}
            error={@error}
            name={@name}
            selected_avatar={@selected_avatar}
            selected_build_index={@selected_build_index}
            selected_skills={@selected_skills}
          />
        </div>
      </div>
    </div>
    """
  end

  attr :skills, :list, required: true
  attr :selected_skills, :list, required: true

  def custom_skill_picker(assigns) do
    ~H"""
    <div class="row text-center mb-3">
      <div class="col">
        <h2><i class="fa fa-cogs mr-1"></i>Custom Build: Choose 3 Skills</h2>
        <a class="btn btn-outline-dark text-white" phx-click="toggle-custom" id="back-to-builds-button">
          <i class="fa fa-arrow-left"></i> Back to Builds
        </a>
      </div>
    </div>
    <div class="row mb-3">
      <div class="col">
        <div class="rounded p-2 darker margin-auto mb-0">
          <div class="row">
            <%= for skill <- @skills do %>
              <div class="col-12 col-sm-6 col-md-3 col-lg-2 col-xl-2 text-center mb-3">
                <img
                  phx-click="pick-skill"
                  phx-value-id={skill.id}
                  src={GH.image_url(skill)}
                  class={"d-none d-md-inline skill img-border-sm #{if Enum.member?(@selected_skills, skill), do: "current"} #{if skill.passive, do: "passive"}"}
                  data-toggle="tooltip"
                  title={GH.skill_description(skill)}
                />
                <img
                  phx-click="pick-skill"
                  phx-value-id={skill.id}
                  src={GH.image_url(skill)}
                  class={"d-inline d-md-none skill img-border-sm #{if Enum.member?(@selected_skills, skill), do: "current"} #{if skill.passive, do: "passive"}"}
                />
                <br />
                <h5 class="mt-0 mb-0">{skill.name}</h5>
                <%= if skill.mp_cost && skill.mp_cost > 0 do %>
                  <span class="badge badge-light-primary" data-toggle="tooltip" title="Energy Cost">
                    <i class="fa fa-bolt mr-1"></i>{skill.mp_cost}
                  </span>
                <% end %>
                <%= if skill.passive do %>
                  <span class="badge badge-light-dark"><i class="fa fa-dot-circle mr-1"></i>Passive</span>
                <% end %>
                <p class="d-block d-md-none text-dark"><em>{skill.description}</em></p>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :role, :string, required: true
  attr :selected_build_index, :integer, default: nil

  def build_picker(assigns) do
    ~H"""
    <div class="row text-center mb-3">
      <div class="col">
        <h2>Pick a Skill Build</h2>
        <a class="btn btn-outline-dark text-white" phx-click="toggle-custom" id="custom-build-button">
          Or create a Custom Build
        </a>
      </div>
    </div>
    <div class="row d-flex align-items-stretch justify-content-around mb-3">
      <%= for {build, index} <- builds_for(@role) |> Enum.with_index() do %>
        <div class="col-12 col-lg">
          <div class="darker rounded text-center p-1 pb-2">
            <h3 class="text-danger">{elem(build, 1)}</h3>
            <p class="font-italic text-muted">(mouse over images for info)</p>
            <div class="row justify-content-center">
              <%= for skill <- elem(build, 0) do %>
                <div class="col">
                  <img
                    src={GH.image_url(skill)}
                    style="width: 70px"
                    class={"img-border-sm tooltip-mobile #{if skill.passive, do: "passive"}"}
                    data-toggle="tooltip"
                    title={GH.skill_description(skill)}
                    id={"skill_build_#{skill.id}_#{index}"}
                  />
                  <br />
                  <strong>{skill.name}</strong>
                </div>
              <% end %>
            </div>
            <div class="row justify-content-center mt-3">
              <%= if @selected_build_index == index do %>
                <a href="javascript:;" class="btn btn-secondary btn-lg col-6 margin-auto disabled">Picked</a>
              <% else %>
                <button
                  type="button"
                  class="btn btn-secondary btn-lg col-6 margin-auto h5"
                  phx-click="pick-build"
                  phx-value-number={index}
                >
                  Pick
                </button>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  attr :custom, :boolean, required: true
  attr :selected_avatar, :map, required: true
  attr :selected_build_index, :integer, default: nil
  attr :selected_skills, :list, required: true

  def selected_skills_bar(assigns) do
    ~H"""
    <div class="py-3 mb-3 darker rounded" id="create-bar">
      <div class="row justify-content-center align-items-center">
        <div class="col">
          <div class="row align-items-center">
            <div class="col text-center font-weight-bold">
              <h4 class="m-0 d-none d-lg-block text-danger">
                {build_title(@selected_avatar, @selected_skills, @selected_build_index)}
              </h4>
            </div>
          </div>
          <div class="skills-container mt-2">
            <%= for skill <- @selected_skills do %>
              <div class="skill-container">
                <img
                  src={GH.image_url(skill)}
                  class={"skill img-border-sm #{if skill.passive, do: "passive"}"}
                  data-toggle="tooltip"
                  title={GH.skill_description(skill)}
                  phx-click="pick-skill"
                  phx-value-id={skill.id}
                  id={"skill_#{skill.id}"}
                />
                <br /><strong class="d-none d-lg-block">{skill.name}</strong>
                <%= if @custom && skill.mp_cost && skill.mp_cost > 0 do %>
                  <div>
                    <span class="badge badge-light-primary" data-toggle="tooltip" title="Energy Cost">
                      <i class="fa fa-bolt mr-1"></i>{skill.mp_cost}
                    </span>
                  </div>
                <% end %>
              </div>
            <% end %>
            <%= if Enum.count(@selected_skills) < 3 do %>
              <%= for _ <- ((Enum.count(@selected_skills) + 1)..3) do %>
                <div class="skill-container">
                  <div class="empty-skill"></div>
                </div>
              <% end %>
            <% end %>
            <div class="skill-container">
              <img
                src={GH.image_url(@selected_avatar.ultimate)}
                class={"skill img-border-sm #{if @selected_avatar.ultimate.passive, do: "passive"}"}
                data-toggle="tooltip"
                title={GH.skill_description(@selected_avatar.ultimate)}
                id={"skill_#{@selected_avatar.ultimate.id}"}
              />
              <br /><strong class="d-none d-lg-block">{@selected_avatar.ultimate.name}</strong>
              <%= if @custom && !@selected_avatar.ultimate.passive do %>
                <div>
                  <span class="badge badge-light-primary" data-toggle="tooltip" title="Energy Cost">
                    <i class="fa fa-bolt mr-1"></i>{@selected_avatar.ultimate.mp_cost}
                  </span>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :current_player, :map, required: true
  attr :custom, :boolean, required: true
  attr :error, :string, default: nil
  attr :name, :string, default: nil
  attr :selected_avatar, :map, required: true
  attr :selected_build_index, :integer, default: nil
  attr :selected_skills, :list, required: true

  def create_submit_panel(assigns) do
    ~H"""
    <%= if Enum.count(@selected_skills) == 3 do %>
      <%= if @current_player && @current_player.user_id do %>
        <div class="row mb-3">
          <div class="col text-center">
            <form phx-change="validate">
              <input
                type="text"
                maxlength="15"
                minlength="3"
                class="form-control text-center"
                name="name"
                value={@current_player.user.username}
                style="max-width: 300px; margin:auto"
                data-toggle="tooltip"
                title="Edit your Hero's name"
              />
              <%= if @error do %>
                <span class="text-danger">{@error}</span>
              <% end %>
            </form>
          </div>
        </div>
        <%= unless @error do %>
          <div class="row">
            <div class="col">
              <button
                class="btn btn-outline-danger dark-bg p-3 btn-block btn-lg"
                phx-click="create"
                phx-hook="Loading"
                loading="Creating..."
                id="create-button"
              >
                <img src={GH.image_url(@selected_avatar)} class="avatar img-border" />
                <strong class="font-20 d-block loading-text">Invoke {@name}</strong>
              </button>
            </div>
          </div>
        <% end %>
      <% else %>
        <.form for={%{}} action="/start" method="post">
          <input type="hidden" name="avatar" value={@selected_avatar.id} />
          <%= for skill <- @selected_skills do %>
            <input type="hidden" name="skills[]" value={skill.id} />
          <% end %>
          <div class="row">
            <div class="col">
              <button class="btn btn-outline-danger dark-bg btn-block btn-lg p-3" type="submit" id="create-button">
                <img src={GH.image_url(@selected_avatar)} class="avatar img-border" />
                <strong class="font-20 d-block loading-text">
                  Invoke a {build_title(@selected_avatar, @selected_skills, @selected_build_index)} {@selected_avatar.name}
                </strong>
              </button>
            </div>
          </div>
        </.form>
      <% end %>
    <% end %>
    """
  end

  attr :avatar, :map, required: true
  attr :avatars, :list, required: true
  attr :selected, :boolean, default: false

  defp background_avatar(assigns) do
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
          <.avatar_stats avatar={@avatar} avatars={@avatars} />
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

  attr :avatar, :map, required: true
  attr :avatars, :list, required: true

  defp avatar_stats(assigns) do
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

  defp roles, do: ["tank", "bruiser", "nuker", "carry", "support"]

  defp build_title(_, selected_skills, nil) when length(selected_skills) > 0, do: "Custom Build"
  defp build_title(_, _, nil), do: "Skill Build"

  defp build_title(avatar, _, index) do
    build = Game.skill_build_for(avatar.role, index)
    elem(build, 1)
  end

  defp builds_for(role), do: Game.skill_builds_for(role)

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
    max = Enum.max_by(avatars, fn current -> current.display_offense end)
    avatar.display_offense * 100 / max.display_offense
  end

  defp display_percentage(:defense, avatar, avatars) do
    max = Enum.max_by(avatars, fn current -> current.display_defense end)
    avatar.display_defense * 100 / max.display_defense
  end

  defp display_percentage(:magic, avatar, avatars) do
    max = Enum.max_by(avatars, fn current -> current.display_magic end)
    avatar.display_magic * 100 / max.display_magic
  end

  defp display_percentage(:speed, avatar, avatars) do
    max = Enum.max_by(avatars, fn current -> current.display_speed end)
    avatar.display_speed * 100 / max.display_speed
  end
end
