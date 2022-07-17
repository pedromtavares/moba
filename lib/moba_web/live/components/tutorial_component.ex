defmodule MobaWeb.TutorialComponent do
  use MobaWeb, :live_component

  @final_training_step 19
  @final_base_step 29
  @final_arena_step 39

  def subscribe(player_id) do
    MobaWeb.subscribe("tutorial-#{player_id}")
    player_id
  end

  def next_step(%{assigns: %{tutorial_step: current_step}} = socket, step)
      when current_step == step - 1 do
    set_step(socket, step)
  end

  def next_step(socket, _), do: socket

  def set_step(%{assigns: %{current_player: player}} = socket, step) when not is_nil(player) do
    Moba.Game.update_tutorial_step!(player, step)

    MobaWeb.broadcast("tutorial-#{player.id}", :tutorial, %{step: step})

    assign(socket, tutorial_step: step)
  end

  def set_step(socket, _), do: socket

  def finish_training(socket), do: set_step(socket, @final_training_step)
  def finish_base(socket), do: set_step(socket, @final_base_step)
  def finish_arena(socket), do: set_step(socket, @final_arena_step)
end
