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

  def next_step(%{assigns: %{tutorial_step: current_step}} = socket, step)
      when current_step == step - 1 do
    set_step(socket, step)
  end

  def next_step(socket, _), do: socket

  def set_step(%{assigns: %{current_hero: hero}} = socket, step) do
    Moba.Accounts.update_tutorial_step!(hero.user, step)

    MobaWeb.broadcast("tutorial-#{hero.id}", "tutorial-step", %{step: step})

    assign(socket, tutorial_step: step)
  end

  def finish(socket), do: set_step(socket, Moba.final_tutorial_step())
end
