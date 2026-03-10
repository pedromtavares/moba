defmodule MobaWeb.V2.Components.ProfileComponents do
  use Phoenix.Component

  slot :progression, required: true
  slot :hero_list, required: true
  slot :rewards_modal

  def dashboard_shell(assigns) do
    ~H"""
    <div class="dashboard mt-2">
      <div class="row">
        <div class="col">
          {render_slot(@progression)}
          {render_slot(@hero_list)}
        </div>
      </div>
    </div>

    {render_slot(@rewards_modal)}
    """
  end

  slot :collection, required: true
  slot :summary, required: true
  slot :ranking, required: true

  def player_profile_shell(assigns) do
    ~H"""
    <div class="user-profile">
      <div class="row mt-2">
        <div class="col-md-6 col-xl-4">
          {render_slot(@collection)}
        </div>
        <div class="col-md-6 col-xl-4">
          {render_slot(@summary)}
        </div>
        <div class="col-md-12 col-xl-4">
          {render_slot(@ranking)}
        </div>
      </div>
    </div>
    """
  end
end
