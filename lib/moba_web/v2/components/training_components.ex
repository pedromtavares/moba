defmodule MobaWeb.V2.Components.TrainingComponents do
  use Phoenix.Component

  attr :pending_battle, :map, default: nil
  attr :hero_dead, :boolean, required: true
  attr :show_farm_tabs, :boolean, required: true
  attr :farm_tab, :string, required: true

  slot :pending
  slot :header, required: true
  slot :dead
  slot :farm_tabs
  slot :meditation
  slot :mine
  slot :gank

  def training_shell(assigns) do
    ~H"""
    <%= if @pending_battle do %>
      {render_slot(@pending)}
    <% else %>
      <div class="row mt-2 training-header">
        <div class="col">
          {render_slot(@header)}
        </div>
      </div>

      <%= if @hero_dead do %>
        <div class="row">
          <div class="col">
            {render_slot(@dead)}
          </div>
        </div>
      <% else %>
        <%= if @show_farm_tabs do %>
          <div class="row">
            <div class="col">
              {render_slot(@farm_tabs)}
            </div>
          </div>
        <% end %>

        <%= case @farm_tab do %>
          <% "meditation" -> %>
            {render_slot(@meditation)}
          <% "mine" -> %>
            {render_slot(@mine)}
          <% _ -> %>
            {render_slot(@gank)}
        <% end %>
      <% end %>
    <% end %>
    """
  end
end
