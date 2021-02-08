defmodule MobaWeb.Tutorial do
  use MobaWeb, :live_component

  def mount(socket) do
    {:ok, socket}
  end

  def render(assigns) do
    MobaWeb.GameView.render("tutorial.html", assigns)
  end

  def subscribe(hero_id) do
    MobaWeb.subscribe("tutorial-#{hero_id}")
    hero_id
  end

  def next_step(%{assigns: %{tutorial_step: current_step, current_hero: hero}} = socket, step)
      when current_step == step - 1 do
    Moba.Accounts.update_tutorial_step!(hero.user, step)

    MobaWeb.broadcast("tutorial-#{hero.id}", "tutorial-step", %{step: step})

    assign(socket, tutorial_step: step)
  end

  def next_step(socket, _), do: socket
end
