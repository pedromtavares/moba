defmodule MobaWeb.V2.Components.CommunityComponents do
  use Phoenix.Component

  slot :intro, required: true
  slot :boards, required: true
  slot :rankings, required: true

  def community_shell(assigns) do
    ~H"""
    <div class="community">
      {render_slot(@intro)}
      {render_slot(@boards)}
      {render_slot(@rankings)}
    </div>
    """
  end
end
