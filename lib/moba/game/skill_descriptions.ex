defmodule Moba.Game.SkillDescriptions do
  @moduledoc "Authored skill explanations. Values come from the specific rank and published version being displayed."
  def describe(s) do
    case s.code do
      "basic_attack" ->
        card(
          "Strike the opponent with your Attack.",
          [effect(:damage, "Damage", formula(s, nil, :atk_multiplier), :damage)],
          []
        )

      "evade" ->
        card("Dodge the next non-ultimate Normal-damage attack.", [], [
          "Does not trigger against magic or Echo Stomp."
        ])

      "blade_fury" ->
        card(
          "Spin through two turns, dealing damage and gaining Armor.",
          [
            effect(:damage, "Damage per turn", formula(s), :damage),
            effect(:armor, "Armor gained", amount(s.armor_amount), :armor)
          ],
          []
        )

      "blink_strike" ->
        card(
          "Repeated casts hit harder for the rest of the battle.",
          [
            effect(:first, "First cast", formula(s), :damage),
            effect(
              :repeat,
              "Further casts",
              formula(s, :base_amount, :other_atk_multiplier),
              :damage
            )
          ],
          []
        )

      "death_pulse" ->
        card("Damage the opponent and restore your Health.", [damage(s), heal(s)], [])

      "decay" ->
        card(
          "Strike and heal yourself using your Attack.",
          [
            effect(:damage, "Damage", formula(s), :damage),
            effect(
              :healing,
              "Healing",
              formula(s, :base_amount, :hp_regen_multiplier),
              :health
            )
          ],
          []
        )

      "double_edge" ->
        card(
          "Deal a heavy hit at the cost of your Health.",
          [
            effect(:damage, "Enemy damage", formula(s), :damage),
            effect(:self_damage, "Self damage", formula(s, nil, :other_atk_multiplier), :damage)
          ],
          []
        )

      "echo_stomp" ->
        card(
          "Charge one turn, then unleash a heavy strike.",
          [
            effect(:damage, "Full release", formula(s), :damage),
            effect(
              :interrupted,
              "If interrupted",
              formula(s, :base_amount, :other_atk_multiplier),
              :damage
            )
          ],
          ["Ignores Evade."]
        )

      "empower" ->
        card(
          "Strike and gain Power for your following turns.",
          [
            effect(:damage, "Damage", formula(s), :damage),
            effect(:power, "Bonus Power", amount(s.power_amount), :power),
            duration(s)
          ],
          []
        )

      "illuminate" ->
        card(
          "Charge one turn, then release a burst of magic.",
          [
            effect(:damage, "Full release", amount(s.base_damage), :damage),
            effect(:interrupted, "If interrupted", amount(s.base_amount), :damage)
          ],
          []
        )

      "lightning_bolt" ->
        card("Blast the opponent with magic damage.", [damage(s)], [])

      "maledict" ->
        card(
          "Strike and empower magic damage on your next turn.",
          [
            damage(s),
            effect(:power, "Power next turn", amount(s.power_amount), :power)
          ],
          []
        )

      "mana_burn" ->
        card(
          "Damage the opponent and burn their Energy.",
          [
            damage(s),
            effect(
              :energy,
              "Energy burned",
              scaled(s.other_mp_multiplier, "enemy max Energy"),
              :energy
            )
          ],
          []
        )

      "mana_shield" ->
        card(
          "Strike and gain Armor based on your maximum Energy.",
          [
            effect(:damage, "Damage", formula(s), :damage),
            effect(:armor, "Armor gained", scaled(s.mp_multiplier, "your max Energy"), :armor)
          ],
          []
        )

      "shadow_word" ->
        card(
          "Curse the opponent or heal yourself over time.",
          [
            effect(:chance, "Healing chance", percentage(s.roll_number), :chance),
            effect(:damage, "Curse per turn", amount(s.base_damage), :damage),
            effect(:healing, "Healing per turn", amount(s.base_amount), :health),
            duration(s)
          ],
          []
        )

      "shuriken_toss" ->
        card(
          "Strike and temporarily reduce the opponent's Armor.",
          [
            effect(:damage, "Damage", formula(s), :damage),
            effect(:armor, "Armor reduction", amount(s.armor_amount), :armor),
            duration(s)
          ],
          []
        )

      "static_link" ->
        card(
          "Strike and steal the opponent's Attack while linked.",
          [
            effect(:damage, "Damage", formula(s), :damage),
            effect(:attack, "Attack stolen", amount(s.base_amount), :attack),
            duration(s)
          ],
          []
        )

      "chakra_magic" ->
        card(
          "Cleanse debuffs, restore Energy, and shorten your cooldowns.",
          [
            effect(:cleanse, "Debuffs cleansed", amount(s.level), :status),
            effect(:energy, "Energy restored", amount(s.base_amount), :energy),
            effect(:cooldowns, "Cooldown reduction", turns(s.extra_amount), :status)
          ],
          []
        )

      "fortunes_end" ->
        card(
          "Deal magic damage and pause the opponent's buffs.",
          [damage(s), effect(:pause, "Buffs paused", turns(s.duration, "enemy turns"), :status)],
          []
        )

      "purifying_flames" ->
        card(
          "Deal heavy magic damage, then heal the opponent over time.",
          [
            damage(s),
            effect(:healing, "Enemy healing per turn", amount(s.base_amount), :health),
            effect(:duration, "Healing lasts", turns(s.duration, "enemy turns"), :status)
          ],
          []
        )

      "counter_helix" ->
        card(
          "Chance to retaliate when the opponent attacks.",
          [effect(:chance, "Retaliation chance", percentage(s.roll_number), :chance), damage(s)],
          []
        )

      "feast" ->
        card(
          "Normal-damage hits restore your Health.",
          [
            effect(
              :healing,
              "Health restored per hit",
              formula(s, :base_amount, :hp_regen_multiplier),
              :health
            )
          ],
          []
        )

      "fiery_soul" ->
        card(
          "Skill casts grant stacking Power for the rest of the battle.",
          [effect(:power, "Power gained per cast", amount(s.power_amount), :power)],
          []
        )

      "fury_swipes" ->
        card(
          "Normal-damage hits stack a bleed and refresh its duration.",
          [
            effect(:damage, "Bleed per stack", amount(s.base_damage, "per turn"), :damage),
            duration(s)
          ],
          []
        )

      "jinada" ->
        card(
          "Normal-damage hits pierce Armor and deal extra damage.",
          [
            effect(:damage, "Bonus damage", amount(s.base_damage), :damage),
            effect(:armor, "Armor pierced", amount(s.armor_amount), :armor)
          ],
          []
        )

      "phase_shift" ->
        card(
          "Chance to become invulnerable when attacked.",
          [effect(:chance, "Trigger chance", percentage(s.roll_number), :chance)],
          []
        )

      "assassinate" ->
        card(
          "Aim for one turn, then fire a powerful shot.",
          [effect(:damage, "Shot damage", formula(s), :damage)],
          ["Stun or silence cancels the shot and resets its cooldown."]
        )

      "bad_juju" ->
        card(
          "Build up Armor and Power on each of your turns.",
          [
            effect(:armor, "Armor per turn", amount(s.armor_amount), :armor),
            effect(:power, "Power per turn", amount(s.power_amount), :power),
            duration(s)
          ],
          []
        )

      "battle_trance" ->
        card(
          "Survive at low Health and gain lasting Armor and Power.",
          [
            effect(
              :threshold,
              "Health threshold",
              percentage(s.base_amount, "max Health"),
              :health
            ),
            effect(:armor, "Armor gained", amount(s.armor_amount), :armor),
            effect(:power, "Power gained", amount(s.power_amount), :power)
          ],
          []
        )

      "borrowed_time" ->
        card(
          "Become invulnerable and heal from the next enemy attack.",
          [
            effect(
              :healing,
              "Healing",
              scaled(s.hp_regen_multiplier, "incoming damage"),
              :health
            )
          ],
          []
        )

      "coup" ->
        card(
          "Chance to pierce Armor on each of your turns.",
          [
            effect(:chance, "Trigger chance", percentage(s.roll_number), :chance),
            effect(:armor, "Armor pierced", amount(s.armor_amount), :armor)
          ],
          []
        )

      "culling_blade" ->
        card(
          "Execute a weakened opponent, or deal a heavy hit.",
          [
            effect(
              :threshold,
              "Execute at or below",
              percentage((s.extra_multiplier || 0) * 100, "enemy max Health"),
              :health
            ),
            effect(:damage, "Otherwise deal", formula(s), :damage)
          ],
          ["Execution ignores invulnerability."]
        )

      "doom" ->
        card(
          "Silence the opponent and deal damage over time.",
          [
            effect(:damage, "Damage per enemy turn", amount(s.base_damage), :damage),
            effect(
              :duration,
              "Silence and damage last",
              turns(s.duration, "enemy turns"),
              :status
            )
          ],
          []
        )

      "dream_coil" ->
        card(
          "Set a coil that damages and stuns next turn.",
          [damage(s), effect(:stun, "Stun", turns(1), :status)],
          []
        )

      "elder_dragon_form" ->
        card(
          "Become a dragon, dealing damage and healing each turn.",
          [
            effect(:damage, "Damage per turn", amount(s.base_damage), :damage),
            effect(:healing, "Healing per turn", amount(s.base_amount), :health),
            effect(:power, "Bonus Power", amount(s.power_amount), :power),
            duration(s)
          ],
          []
        )

      "gods_strength" ->
        card(
          "Greatly empower your next Normal-damage attacks.",
          [
            effect(:power, "Bonus Power", amount(s.power_amount), :power),
            duration(s)
          ],
          []
        )

      "guardian_angel" ->
        card(
          "Gain Armor and regenerate Health for your following turns.",
          [
            effect(:healing, "Healing per turn", amount(s.base_amount), :health),
            effect(:armor, "Armor gained", amount(s.armor_amount), :armor),
            duration(s)
          ],
          []
        )

      "laguna_blade" ->
        card(
          "Deliver a pure-damage strike through the opponent's defenses.",
          [effect(:damage, "Damage", formula(s), :damage)],
          ["Ignores Armor and invulnerability."]
        )

      "life_drain" ->
        card(
          "Drain Health over two turns, healing on each hit.",
          [
            effect(:damage, "Damage per turn", amount(s.base_damage), :damage),
            effect(
              :healing,
              "Healing per turn",
              formula(s, :base_amount, :hp_regen_multiplier, "max Energy"),
              :health
            ),
            effect(:interrupted, "Damage if interrupted", amount(s.extra_amount), :damage)
          ],
          []
        )

      "mana_void" ->
        card(
          "Strike with magic, restore Energy, and drain the opponent's Energy.",
          [
            damage(s),
            effect(:energy, "Energy restored", amount(s.base_amount), :energy),
            effect(:drain, "Energy drained", amount(s.base_amount), :energy)
          ],
          []
        )

      "omnislash" ->
        card(
          "Unleash a powerful strike with a chance for maximum damage.",
          [
            effect(:chance, "Max-hit chance", percentage(s.roll_number), :chance),
            effect(:minimum, "Minimum damage", formula(s), :damage),
            effect(
              :maximum,
              "Maximum damage",
              formula(s, :base_damage, :other_atk_multiplier),
              :damage
            )
          ],
          []
        )

      "psionic_trap" ->
        card(
          "Set a trap that damages and weakens the opponent next turn.",
          [
            damage(s),
            effect(:armor, "Armor reduction", amount(s.armor_amount), :armor),
            effect(
              :attack,
              "Attack reduction",
              scaled(s.atk_multiplier, "base Attack"),
              :attack
            ),
            duration(s)
          ],
          []
        )

      "pulse_nova" ->
        card(
          "Pulse magic damage every turn while using other skills.",
          [effect(:damage, "Magic damage per pulse", amount(s.base_damage), :damage)],
          ["Stops when you run out of Energy."]
        )

      "rearm" ->
        card(
          "Reset cooldowns and repeat your last skill.",
          [
            effect(:power, "Bonus Power", amount(s.power_amount), :power),
            effect(:fallback, "Fallback damage", formula(s, nil, :atk_multiplier), :damage)
          ],
          ["Also pays the repeated skill's Energy cost."]
        )

      "remote_mines" ->
        card(
          "Plant a mine that explodes on your next turn.",
          [
            effect(
              :damage,
              "Explosion damage",
              formula(s, :base_damage, :mp_multiplier, "max Energy"),
              :damage
            )
          ],
          []
        )

      "rupture" ->
        card(
          "Strike with magic, then reflect damage you receive.",
          [
            damage(s),
            effect(
              :reflect,
              "Damage reflected",
              scaled(s.extra_multiplier, "actual damage received"),
              :damage
            ),
            effect(:duration, "Reflection lasts", turns(s.duration, "enemy turns"), :status)
          ],
          []
        )

      "spell_steal" ->
        card(
          "Copy the opponent's last skill and gain Power.",
          [
            effect(:power, "Bonus Power", amount(s.power_amount), :power),
            effect(
              :fallback,
              "Fallback damage",
              formula(s, nil, :atk_multiplier),
              :damage
            )
          ],
          ["Deal the fallback hit if nothing can be copied."]
        )

      "sunder" ->
        card(
          "Steal Health from the opponent to restore your own.",
          [effect(:steal, "Health stolen", amount(s.base_amount), :health)],
          []
        )

      "time_lapse" ->
        card(
          "Rewind your Health and repeat part of your previous damage.",
          [
            effect(:damage, "Damage", scaled(s.extra_multiplier, "previous-turn damage"), :damage)
          ],
          []
        )

      "walrus_punch" ->
        card(
          "Strike and stun the opponent immediately.",
          [
            effect(:damage, "Damage", formula(s), :damage),
            effect(:stun, "Stun", turns(1), :status)
          ],
          []
        )

      "boss_bash" ->
        card(
          "Roshan's attacks have a chance to stun.",
          [effect(:chance, "Stun chance", percentage(s.roll_number), :chance)],
          []
        )

      "boss_slam" ->
        card("Roshan slams the ground for heavy damage.", [damage(s)], [])

      "boss_spell_block" ->
        card("Automatically block stun and silence when ready.", [], [])

      "boss_ult" ->
        card(
          "Gain stacking Armor and Power every turn.",
          [
            effect(:armor, "Armor gained per turn", amount(s.armor_amount), :armor),
            effect(:power, "Power gained per turn", amount(s.power_amount), :power)
          ],
          []
        )

      _ ->
        card(Map.get(s, :description) || "", [])
    end
  end

  def summary(skill) do
    describe(skill).summary
  end

  def plain_effects(skill) do
    content = describe(skill)

    Enum.map(content.effects, &"#{&1.label}: #{value_text(&1.value)}")
    |> Kernel.++(content.notes)
    |> Enum.join("\n")
  end

  def value_text(terms) do
    Enum.map_join(terms, " + ", &term_text/1)
  end

  def term_text(%{amount: n, unit: nil}) do
    number(n)
  end

  def term_text(%{amount: n, unit: unit}) do
    "#{number(n)}#{if String.starts_with?(unit, "%") do
      ""
    else
      " "
    end}#{unit}"
  end

  def number(n) when is_integer(n) do
    to_string(n)
  end

  def number(n) when is_float(n) do
    n
    |> Float.round(3)
    |> then(fn v ->
      if v == trunc(v) do
        to_string(trunc(v))
      else
        to_string(v)
      end
    end)
  end

  def number(_) do
    "0"
  end

  defp card(summary, effects, notes \\ []) do
    %{summary: summary, effects: effects, notes: notes, authored: true}
  end

  defp effect(key, label, value, tone) do
    %{key: key, label: label, value: value, tone: tone}
  end

  defp amount(n, unit \\ nil) do
    [%{amount: n || 0, unit: unit}]
  end

  defp percentage(n, of \\ nil) do
    amount(
      n,
      if of do
        "% #{of}"
      else
        "%"
      end
    )
  end

  defp scaled(n, of) do
    percentage((n || 0) * 100, of)
  end

  defp turns(n, unit \\ "turns") do
    amount(
      n,
      if n == 1 && unit == "turns" do
        "turn"
      else
        unit
      end
    )
  end

  defp duration(s) do
    effect(:duration, "Duration", turns(s.duration), :status)
  end

  defp damage(s) do
    effect(:damage, "Damage", amount(s.base_damage), :damage)
  end

  defp heal(s) do
    effect(:healing, "Healing", amount(s.base_amount), :health)
  end

  defp formula(s, base \\ :base_damage, multiplier \\ :atk_multiplier, stat \\ "Attack") do
    flat = base && Map.get(s, base)
    coefficient = multiplier && Map.get(s, multiplier)

    terms =
      if flat && flat != 0 do
        amount(flat)
      else
        []
      end ++
        if coefficient && coefficient != 0 do
          scaled(coefficient, stat)
        else
          []
        end

    if terms == [] do
      amount(0)
    else
      terms
    end
  end
end
