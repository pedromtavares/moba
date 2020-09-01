defmodule MobaWeb.LibraryView do
  use MobaWeb, :view

  def ultimates_for(avatar, ultimates) do
    Enum.filter(ultimates, fn ult -> ult.code == avatar.ultimate_code end) |> Enum.sort_by(fn ult -> ult.level end)
  end
end
