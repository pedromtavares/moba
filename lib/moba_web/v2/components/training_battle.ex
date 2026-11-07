defmodule MobaWeb.V2.Components.TrainingBattle do
  @moduledoc "Training presentation shared by canonical Battle and Match pages."
  use MobaWeb, :v2_html

  def page(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_player={@current_player}
      current_hero={@current_hero}
      preview={@preview}
      sidebar_code="training"
      hide_footer
      hide_sidebar
    >
      <main class="team-battle-page" id="team-battle-page">
        <.live_component
          module={MobaWeb.V2.TrainingBattleComponent}
          id={"team-encounter-#{@training_record.id}-#{@training_battle_index || "group"}"}
          training_team_id={@training_record.team_run_id}
          encounter_id={@training_record.id}
          battle_index={@training_battle_index}
          page_navigation={true}
          current_scope={@current_scope}
          access_session={@access_session}
        />
      </main>
    </Layouts.app>
    """
  end
end
