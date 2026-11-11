defmodule MobaWeb.V2.Components.ArenaBattle do
  use MobaWeb, :v2_html

  def page(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_player={@current_player}
      current_hero={@current_hero}
      preview={true}
      sidebar_code="arena"
      hide_footer={true}
      hide_sidebar={true}
    >
      <main id="arena-battle-page" class="team-battle-page arena-battle-page">
        <.live_component
          module={MobaWeb.V2.ArenaBattleComponent}
          id={"arena-match-#{@arena_match_id}"}
          battle_id={Map.get(assigns, :arena_battle_id)}
          match_id={@arena_match_id}
          current_scope={@current_scope}
          access_session={@access_session}
          battle_speed={@battle_speed}
        />
      </main>
    </Layouts.app>
    """
  end
end
