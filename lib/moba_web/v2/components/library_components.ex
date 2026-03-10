defmodule MobaWeb.V2.Components.LibraryComponents do
  use Phoenix.Component

  slot :intro, required: true
  slot :guides, required: true
  slot :avatars, required: true
  slot :skills, required: true

  def library_shell(assigns) do
    ~H"""
    <div class="content" id="library">
      {render_slot(@intro)}
      {render_slot(@guides)}
      {render_slot(@avatars)}
      {render_slot(@skills)}
    </div>
    """
  end
end
