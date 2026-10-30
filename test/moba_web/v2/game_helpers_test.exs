defmodule MobaWeb.V2.GameHelpersTest do
  use ExUnit.Case, async: true

  alias MobaWeb.V2.Components.GameHelpers

  test "preview minute labels cap durations above 99 minutes" do
    for minutes <- [0, 1, 98, 99] do
      assert GameHelpers.minutes_label(minutes, true) == minutes
    end

    for minutes <- [100, 341_792] do
      assert GameHelpers.minutes_label(minutes, true) == "99+"
      assert GameHelpers.minutes_label(minutes, false) == minutes
    end

    assert GameHelpers.minutes_label(nil, true) == nil
  end
end
