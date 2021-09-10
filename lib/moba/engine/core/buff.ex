defmodule Moba.Engine.Core.Buff do
  @moduledoc """
  Struct used for managing multi-turn effects
  """

  @derive Jason.Encoder

  defstruct resource: %{}, duration: 0, power: 0, armor: 0, atk: 0
end
