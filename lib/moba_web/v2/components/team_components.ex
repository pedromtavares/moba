defmodule MobaWeb.V2.Components.TeamComponents do
  use MobaWeb, :v2_html
  import MobaWeb.CoreComponents, only: [icon: 1]

  embed_templates "team_components/*"

  attr :entries, :list, required: true
  attr :current_id, :integer, required: true

  def ranking(assigns) do
    assigns
    |> assign(:standing, Enum.find(assigns.entries, &(&1.team.id == assigns.current_id)))
    |> assign(:entries, Enum.filter(assigns.entries, &(&1.position <= 50)))
    |> rankings()
  end

  def display_name(%{name: name}) when is_binary(name), do: name
  def display_name(%{player: %{user: %{username: username}}}), do: username
  def display_name(_team), do: "Team 3v3"

  attr :entry, :map, required: true
  attr :current_id, :integer, required: true

  defp team_ranking_entry(assigns) do
    ~H"""
    <tr
      id={"team-ranking-#{@entry.team.id}"}
      data-current={to_string(@entry.team.id == @current_id)}
      phx-container="#team-ranking-scroll"
      phx-hook={if @entry.team.id == @current_id && @entry.position <= 50, do: "HalfScroll"}
    >
      <td class="hero-ranking-position"><span>#{@entry.position}</span></td>
      <td>
        <.link
          navigate={~p"/teams/#{@entry.team.id}"}
          class="hero-ranking-identity"
          aria-current={if @entry.team.id == @current_id, do: "page"}
        >
          <div class="team-ranking-roster">
            <img :for={hero <- @entry.team.heroes} src={GH.image_url(hero.avatar)} alt={hero.avatar.name} />
          </div>
          <div>
            <strong>{display_name(@entry.team)}</strong>
            <small>
              {Enum.map_join(@entry.team.heroes, " · ", & &1.avatar.name)}
            </small>
          </div>
        </.link>
      </td>
      <td class="hero-ranking-farm" title={Float.round(@entry.team.total_farm / 3, 2)}>
        <img src={"/images/league/#{@entry.team.league_tier}.png"} alt={Moba.leagues()[@entry.team.league_tier]} />
        <strong>{GH.farming_amount_label(div(@entry.team.total_farm, 3))}</strong>
      </td>
      <td class="hero-ranking-time">
        <strong title={"#{@entry.team.duration_seconds} seconds"}>
          {GH.minutes_label(div(@entry.team.duration_seconds, 60), true)}
        </strong>
        <small>min</small>
      </td>
    </tr>
    """
  end
end
