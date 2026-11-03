defmodule Moba.Game.ItemDescriptions do
  @moduledoc "Authored item explanations using the values of the displayed item record."

  def describe(item) do
    case item.code do
      code when code in ["blades_of_attack", "chainmail"] ->
        card(nil)

      code when code in ["boots_of_speed", "phase_boots", "boots_of_travel"] ->
        card(nil, [], boots_note())

      "arcane_boots" ->
        card(
          "Activate to restore Energy.",
          [effect(:energy, "Energy restored", item.base_amount, :energy)],
          boots_note()
        )

      "tranquil_boots" ->
        card("Activate to restore Health.", [effect(:healing, "Healing", item.base_amount, :health)], boots_note())

      "ring_of_tarrasque" ->
        card("Restore Health on each of your turns.", [effect(:healing, "Healing per turn", item.base_amount, :health)])

      "sages_mask" ->
        card("Restore Energy on each of your turns.", [effect(:energy, "Energy per turn", item.base_amount, :energy)])

      "magic_stick" ->
        card("Activate to restore Health and Energy.", [
          effect(:healing, "Healing", item.base_amount, :health),
          effect(:energy, "Energy restored", item.extra_amount, :energy)
        ])

      "shadow_blade" ->
        card("Deal bonus damage when you start a battle.", [
          effect(:damage, "Opening damage", item.base_amount, :damage)
        ])

      "vanguard" ->
        card("Chance to block incoming damage on each enemy turn.", [
          effect(:chance, "Block chance", item.roll_number, :chance, "%"),
          effect(:blocked, "Damage blocked", item.base_amount, :armor)
        ])

      "pipe_of_insight" ->
        card("Activate to gain Armor for the next enemy turn.", [
          effect(:armor, "Temporary Armor", item.armor_amount, :armor)
        ])

      "maelstrom" ->
        card("Chance to unleash bonus damage on each of your turns.", [
          effect(:chance, "Trigger chance", item.roll_number, :chance, "%"),
          effect(:damage, "Bonus damage", item.base_amount, :damage)
        ])

      "assault_cuirass" ->
        card("Pierce enemy Armor on each of your turns.", [effect(:armor, "Armor pierced", item.armor_amount, :armor)])

      "diffusal_blade" ->
        card("Burn enemy Energy and deal bonus damage each turn.", [
          percent(:damage, "Bonus damage", item.mp_multiplier, :damage, "enemy max Energy"),
          percent(:energy, "Energy burned", item.other_mp_multiplier, :energy, "enemy max Energy")
        ])

      code when code in ["dagon", "dagon5"] ->
        card("Blast the enemy, turning this turn's damage into Magic Damage.", [
          effect(:damage, "Bonus damage", item.base_amount, :damage)
        ])

      "heavens_halberd" ->
        card("Disarm the enemy, preventing Normal damage for one turn.")

      "bkb" ->
        card("Become immune to stun, silence, and disarm.", [
          effect(:duration, "Immunity lasts", item.duration, :status, "turn")
        ])

      "bloodstone" ->
        card("Steal part of the enemy's healing.", [
          percent(:healing, "Healing stolen", item.hp_regen_multiplier, :health, "enemy healing"),
          duration(item)
        ])

      "octarine_core" ->
        card("Reduce all running skill and item cooldowns.", [
          effect(:cooldowns, "Cooldown reduction", item.extra_amount, :status, "turns")
        ])

      "soul_booster" ->
        card("Restore Energy each turn. Activate for an extra burst.", [
          effect(:energy, "Energy restored", item.base_amount, :energy),
          effect(:passive_energy, "Energy per turn", item.extra_amount, :energy)
        ])

      "silver_edge" ->
        card("Strike harder when starting battle. Activate to reduce enemy healing.", [
          effect(:damage, "Opening damage", item.base_amount, :damage),
          percent(:healing, "Healing reduction", item.hp_regen_multiplier, :health),
          duration(item)
        ])

      "daedalus" ->
        card("Chance to pierce extra Armor on each of your turns.", [
          effect(:chance, "Trigger chance", item.roll_number, :chance, "%"),
          effect(:armor, "Armor pierced", item.armor_amount, :armor)
        ])

      "scythe_of_vyse" ->
        card("Chance to gain Power each turn. Activate to stun the enemy.", [
          effect(:chance, "Trigger chance", item.roll_number, :chance, "%"),
          effect(:power, "Temporary Power", item.power_amount, :power),
          effect(:stun, "Stun", 1, :status, "turn")
        ])

      "satanic" ->
        card("Activate to heal from the damage you deal this turn.", [
          percent(:healing, "Healing", item.hp_regen_multiplier, :health, "damage dealt")
        ])

      "shivas_guard" ->
        card("Blast the enemy and gain Armor for their next turn.", [
          effect(:damage, "Bonus damage", item.base_amount, :damage),
          effect(:armor, "Temporary Armor", item.armor_amount, :armor)
        ])

      "orchid_malevolence" ->
        card("Activate to pierce Armor and silence the enemy.", [
          effect(:armor, "Armor pierced", item.armor_amount, :armor)
        ])

      "linkens_sphere" ->
        card("Automatically block disables when stunned or silenced.", [], [
          "Protects against stun, silence, and disarm."
        ])

      _ ->
        %{summary: item.description, effects: [], notes: [], authored: false}
    end
  end

  defp card(summary, effects \\ [], notes \\ []),
    do: %{summary: summary, effects: effects, notes: notes, authored: true}

  defp effect(key, label, amount, tone, unit \\ nil),
    do: %{key: key, label: label, value: [%{amount: amount, unit: unit}], tone: tone}

  defp percent(key, label, multiplier, tone, unit \\ ""),
    do: effect(key, label, multiplier * 100, tone, String.trim("% " <> unit))

  defp duration(item), do: effect(:duration, "Duration", item.duration, :status, "enemy turns")
  defp boots_note, do: ["Speed bonuses from Boots do not stack."]
end
