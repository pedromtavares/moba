defmodule Moba.Engine.Core.Buff do
  @moduledoc """
  Struct used for managing multi-turn effects
  """

  @derive Jason.Encoder

  defstruct resource: %{}, duration: 0, power: 0, armor: 0, atk: 0, resource_code: nil, level: nil, applied_order: 0
  def code(%{"resource_code" => code}), do: code
  def code(%{resource: %{code: code}}), do: code
  def code(%{resource_code: code}), do: code
end
