defmodule Moba.Engine.Core.BuffPause do
  @moduledoc """
  Keeps buff bonuses and timers intact while Fortune's End suppresses their effects.
  """

  alias Moba.Engine.Core.Buff

  @stats ~w(battle_armor turn_armor next_armor battle_power turn_power next_power
    battle_power_normal turn_power_normal next_power_normal battle_power_magic
    turn_power_magic next_power_magic turn_atk)a
  @flags ~w(invulnerable physically_invulnerable inneffectable immortal undisarmable)a

  def active?(battler) do
    Enum.any?(battler.attacker_debuffs, &(Buff.code(&1) == "fortunes_end" && &1.duration > 0))
  end

  # The snapshot also keeps the final suppressed turn paused after its timer ticks to zero.
  def paused?(battler), do: map_size(battler.paused_bonuses) > 0 || active?(battler)

  @stat_keys Enum.map(@stats, &Atom.to_string/1)
  @flag_keys Enum.map(@flags, &Atom.to_string/1)
  @buff_keys [:buffs, :defender_buffs, :pulse_nova, "buffs", "defender_buffs", "pulse_nova"]

  def deferred_effect?(key, value) when key in @stats or key in @stat_keys, do: is_number(value) && value > 0
  def deferred_effect?(key, value) when key in @flags or key in @flag_keys, do: value == true
  def deferred_effect?(key, value) when key in @buff_keys, do: value not in [nil, false, "false", ""]
  def deferred_effect?(_key, _value), do: false

  def suppress(battler) do
    if paused?(battler) do
      battler = %{battler | paused_bonuses: Map.put(battler.paused_bonuses, "active", true)}

      battler =
        Enum.reduce(@stats, battler, fn stat, acc ->
          value = Map.fetch!(acc, stat)
          key = Atom.to_string(stat)
          saved = Map.get(acc.paused_bonuses, key, 0) + max(value, 0)
          %{Map.put(acc, stat, min(value, 0)) | paused_bonuses: Map.put(acc.paused_bonuses, key, saved)}
        end)

      Enum.reduce(@flags, battler, fn flag, acc ->
        key = Atom.to_string(flag)
        saved = Map.get(acc.paused_bonuses, key, false) || Map.fetch!(acc, flag)
        %{Map.put(acc, flag, false) | paused_bonuses: Map.put(acc.paused_bonuses, key, saved)}
      end)
    else
      battler
    end
  end

  def resume(battler, own_turn \\ false) do
    if map_size(battler.paused_bonuses) > 0 && !active?(battler) do
      saved = battler.paused_bonuses

      battler =
        Enum.reduce(@stats, battler, fn stat, acc ->
          Map.update!(acc, stat, &(&1 + Map.get(saved, Atom.to_string(stat), 0)))
        end)

      battler =
        Enum.reduce(@flags, battler, fn flag, acc ->
          Map.update!(acc, flag, &(&1 || Map.get(saved, Atom.to_string(flag), false)))
        end)

      # A cleanse can resume ticks skipped earlier in this same turn. Keep their
      # trace, but let the subsequent applied effects describe the active buff.
      effects =
        if own_turn do
          Enum.map(battler.effects, fn event ->
            if event["key"] in [:buff_paused, "buff_paused"], do: Map.put(event, "resumed", true), else: event
          end)
        else
          battler.effects
        end

      event = %{
        "key" => "buffs_resumed",
        "value" => true,
        "resource" => "fortunes_end",
        "priority" => 5,
        "paused" => false
      }

      battler = %{battler | paused_bonuses: %{}, effects: effects ++ [event]}

      if own_turn do
        Enum.reduce(
          [
            next_armor: :turn_armor,
            next_power: :turn_power,
            next_power_normal: :turn_power_normal,
            next_power_magic: :turn_power_magic
          ],
          battler,
          fn {next, current}, acc ->
            acc |> Map.update!(current, &(&1 + Map.fetch!(acc, next))) |> Map.put(next, 0)
          end
        )
      else
        battler
      end
    else
      battler
    end
  end
end
