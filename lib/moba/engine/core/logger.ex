defmodule Moba.Engine.Core.Logger do
  @moduledoc """
  Bundles and displays text translations to all effects in a given Turn.

  The following codes are used to sprinkle some color on important parts of the text:
   - [damage]this text will turn red, used for damage[/damage]
   - [armor]this text will turn yellow, also used for alternate damage[/armor]
   - [hp]this text will turn green, used mostly for hp regen[/hp]
   - [mp]this text will turn blue, used mostly for mp regen[/mp]
   - [power]this text will turn pink, used for power[/power]
   - [status]this text will turn grey, used for status changes like stuns[/status]
  """

  @skipped_effects ["last_skill", "current_mp", "double_skill", "damage_type", "buffs", "debuffs"]
  @skipped_resources ["stunned"]

  @doc """
  Groups effects from both the attacker and defender and properly lists them according to their priority
  """
  def descriptions_for(turn) do
    attacker_effects = Enum.map(turn.attacker.effects, fn effect -> Map.put(effect, "hero", turn.attacker.name) end)
    defender_effects = Enum.map(turn.defender.effects, fn effect -> Map.put(effect, "hero", turn.defender.name) end)
    heroes = %{attacker: turn.attacker.name, defender: turn.defender.name}

    (attacker_effects ++ defender_effects)
    |> Enum.reject(fn effect -> Enum.member?(@skipped_effects, key_string(effect["key"])) end)
    |> Enum.reject(fn effect -> Enum.member?(@skipped_resources, key_string(effect["resource"])) end)
    |> Enum.sort_by(fn effect -> effect["priority"] end)
    |> grouped_effects()
    # |> IO.inspect()
    |> Enum.map(fn {key, val} -> {key, description_for(key, val, heroes)} end)
  end

  defp grouped_effects(effects) do
    effects
    # base grouping by resource
    |> Enum.group_by(fn effect -> effect["resource"] end)
    # order by priority, skill -> item -> rest
    |> Enum.sort_by(fn {_key, value} -> hd(value)["priority"] end)
    # resource => {key, hero}, so effects with the same key applied to both heroes are separated.
    |> Enum.map(fn {key, val} ->
      {key,
       Enum.group_by(val, fn effect ->
         {key_string(effect["key"]), effect["hero"]}
       end)}
    end)
    # aggregate multiple effects with same key into one summed up result, differentiated by hero
    |> Enum.map(fn {key, val} ->
      {
        key,
        Enum.map(val, fn {{key, hero}, val} ->
          {key,
           Enum.reduce(val, {0, hero}, fn effect, {acc, hero} ->
             {sum_value(acc, effect["value"]), hero}
           end)}
        end)
        # after summing, group by key again - "damage" => [{sum1, hero1}, {sum2, hero2}]
        |> Enum.group_by(fn {key, _} -> key end, fn {_, val} -> val end)
        # transform single element arrays to single value for easier matching
        |> Enum.map(fn {key, val} ->
          if Enum.count(val) == 1 do
            {key, hd(val)}
          else
            {key, Enum.sort_by(val, fn effect -> elem(effect, 0) end)}
          end
        end)
        |> Enum.into(%{})
      }
    end)
  end

  defp key_string(key) when is_atom(key), do: Atom.to_string(key)

  defp key_string(key), do: key

  defp sum_value(acc, value) when is_number(value), do: acc + value

  defp sum_value(_, value), do: value

  # ------------------------------------------ DESCRIPTIONS

  defp description_for("blade_fury", %{"damage" => {damage, defender}, "next_armor" => {armor, attacker}}, _) do
    "#{attacker} is spinning furiously, increasing [armor]Armor by #{armor}[/armor] and dealing [damage]#{damage} damage[/damage] to #{
      defender
    }"
  end

  defp description_for("blink_strike", %{"damage" => {damage, defender}, "extra" => {true, attacker}}, _) do
    "#{attacker} blinked behind #{defender} with even deadlier force, dealing [damage]#{damage} damage[/damage]"
  end

  defp description_for("blink_strike", %{"damage" => {damage, defender}}, heroes) do
    "Out of nowhere, #{opponent_for(defender, heroes)} appeared behind #{defender} dealing [damage]#{damage} damage[/damage]"
  end

  defp description_for("counter_helix", %{"damage" => {damage, hero}}, heroes) do
    "#{opponent_for(hero, heroes)} spun rapidly in self-defense, dealing [damage]#{damage} damage to #{hero}[/damage]"
  end

  defp description_for("death_pulse", %{"damage" => {damage, defender}, "hp_regen" => {regen, attacker}}, _) do
    "A skull of undeath was conjured to [damage]damage #{defender} for #{damage}[/damage] and [hp]regenerate #{attacker} for #{
      regen
    } HP[/hp]"
  end

  defp description_for("decay", %{"damage" => {damage, defender}, "hp_regen" => {regen, attacker}}, _) do
    "#{attacker} decayed the earth underneath to [hp]renegerate #{regen} HP[/hp] while dealing [damage]#{damage} damage[/damage] to #{
      defender
    }"
  end

  defp description_for("double_edge", %{"damage" => [{self_damage, attacker}, {damage, defender}]}, _) do
    "With almost unnecessary force, #{attacker} self-inflicted [armor]#{self_damage} damage[/armor] to deal [damage]#{
      damage
    } damage[/damage] to #{defender}"
  end

  defp description_for("echo_stomp", %{"charging" => {true, defender}}, _) do
    "#{defender} is connecting with the [status]Astral Spirit ...[/status]"
  end

  defp description_for("echo_stomp", %{"damage" => {damage, defender}}, heroes) do
    "#{opponent_for(defender, heroes)} and the [status]Astral Spirit[/status] both stomped the ground dealing [damage]#{
      damage
    } damage[/damage] to #{defender}"
  end

  defp description_for("illuminate", %{"charging" => {true, defender}}, _) do
    "#{defender} is charging a huge beam of light.."
  end

  defp description_for("illuminate", %{"damage" => {damage, defender}}, _heroes) do
    "#{defender} has seen the light, taking [damage]#{damage} damage[/damage]"
  end

  defp description_for("empower", %{"damage" => {damage, defender}, "turn_power" => {power, attacker}}, _) do
    "Deeply energized, #{attacker} dealt [damage]#{damage} damage[/damage] to #{defender} while also [power]gaining #{
      power
    } Power[/power]"
  end

  defp description_for("empower", %{"turn_power" => {power, attacker}}, _) do
    "Deeply energized, #{attacker} [power]gained #{power} Power[/power] this turn"
  end

  defp description_for("feast", %{"hp_regen" => {regen, attacker}}, _) do
    "Feasting on the opponents life energies, #{attacker} [hp]regenerated #{regen} HP[/hp]"
  end

  defp description_for("fiery_soul", %{"battle_power" => {power, attacker}}, _) do
    "#{attacker} gained [power]#{power} Power[/power] by casting a skill"
  end

  defp description_for("fury_swipes", %{"damage" => {damage, defender}}, heroes) do
    "#{opponent_for(defender, heroes)} opened a serious wound in #{defender}, dealing [damage]#{damage} damage[/damage]"
  end

  defp description_for("jinada", %{"damage" => {damage, defender}, "turn_power" => {power, attacker}}, _) do
    "A master of Jinada, #{attacker} dealt [damage]#{damage} damage[/damage] to #{defender} while also [power]gaining #{
      power
    } Power[/power] this turn"
  end

  defp description_for("maledict", %{"damage" => {damage, defender}, "next_power_magic" => {power, attacker}}, _) do
    "#{attacker} cursed #{defender}, dealing [damage]#{damage} damage[/damage] and granting [power]#{power} Power[/power] for the next skill cast"
  end

  defp description_for("mana_burn", %{"damage" => {damage, defender}, "mp_burn" => {burn, _}}, _) do
    "#{defender} was burned for [mp]#{burn} MP[/mp], also taking [damage]#{damage} damage[/damage] in the process"
  end

  defp description_for("mana_shield", %{"damage" => {damage, defender}, "next_armor" => {armor, attacker}}, _) do
    "#{attacker} is surrounded by a bubble of magic, increasing [armor]Armor by #{armor}[/armor] and dealing [damage]#{
      damage
    } damage[/damage] to #{defender}"
  end

  defp description_for("lightning_bolt", %{"damage" => {damage, defender}}, heroes) do
    "#{opponent_for(defender, heroes)} electrified #{defender} dealing [damage]#{damage} damage[/damage]"
  end

  defp description_for("phase_shift", %{"invulnerable" => {true, hero}}, _) do
    "#{hero} phased out of existence and is [status]invulnerable[/status] this turn, negating all damage taken"
  end

  defp description_for("shadow_word", %{"damage" => {damage, defender}, "hp_regen" => {regen, attacker}}, _) do
    "Cursed by the shadows, #{defender} took [damage]#{damage} damage[/damage] while #{attacker} regenerated [hp]#{
      regen
    } HP[/hp]"
  end

  defp description_for("shadow_word", %{"damage" => {damage, defender}}, _) do
    "Cursed by the shadows, #{defender} took [damage]#{damage} damage[/damage]"
  end

  defp description_for("shadow_word", %{"hp_regen" => {regen, attacker}}, _) do
    "Benevolently cursed by the shadows, #{attacker} regenerated [hp]#{regen} HP[/hp]"
  end

  defp description_for("shuriken_toss", %{"damage" => {damage, defender}, "turn_armor" => {armor, _}}, heroes)
       when armor < 0 do
    "Apparently a ninja now, #{opponent_for(defender, heroes)} threw a shuriken at #{defender} dealing [damage]#{damage} damage[/damage] and piercing [armor]#{
      armor * -1
    } Armor[/armor] for this turn"
  end

  defp description_for("shuriken_toss", %{"damage" => {damage, defender}}, heroes) do
    "Apparently a ninja now, #{opponent_for(defender, heroes)} threw a shuriken at #{defender} dealing [damage]#{damage} damage[/damage]"
  end

  defp description_for("static_link", %{"damage" => {damage, defender}, "turn_atk" => {atk, _}}, heroes) do
    "#{opponent_for(defender, heroes)} linked with #{defender}'s powers, dealing [damage]#{damage} damage[/damage] and [hp]sapping #{
      atk * -1
    } ATK[/hp]"
  end

  defp description_for("static_link", %{"turn_atk" => {atk, defender}}, heroes) do
    "#{opponent_for(defender, heroes)} is still linked with #{defender}, [hp]sapping #{atk * -1} ATK[/hp]"
  end

  # ULTIMATES

  defp description_for("assassinate", %{"charging" => {true, hero}}, _) do
    "#{hero} is taking aim..."
  end

  defp description_for("assassinate", %{"damage" => {damage, defender}}, heroes) do
    "#{opponent_for(defender, heroes)} shot a massive bullet right in the face of #{defender}, dealing [damage]#{damage} damage[/damage]"
  end

  defp description_for("assassinate", %{"charging" => {_, hero}}, _) do
    "#{hero} was interrupted but immediately reloaded the gun, ready to fire again"
  end

  defp description_for("bad_juju", %{"next_armor" => {armor, hero}, "turn_power" => {power, _}}, _) do
    "Dark incantations gave #{hero} extra [armor]#{armor} Armor[/armor] and [power]#{power} Power[/power] this turn"
  end

  defp description_for(
         "battle_trance",
         %{"battle_power" => {power, hero}, "battle_armor" => {armor, _}},
         _
       )
       when power > 0 or armor > 0 do
    "#{hero} refuses to die and has negated all further damage this turn, also gaining [power]#{power} Power[/power] and [armor]#{
      armor
    } Armor[/armor] for the rest of the battle"
  end

  defp description_for("battle_trance", %{"battle_power" => {_, hero}}, _) do
    "#{hero} refuses to die and has negated all further damage this turn"
  end

  defp description_for("borrowed_time", %{"invulnerable" => {true, hero}}, _) do
    "Evoking powers of undeath, #{hero} has become [status]invulnerable[/status] until the next turn"
  end

  defp description_for("borrowed_time", %{"hp_regen" => {regen, hero}}, heroes) do
    "Surrounded by undeath, #{hero} has regenereated [hp]#{regen} HP[/hp] from damage dealt by #{
      opponent_for(hero, heroes)
    }"
  end

  defp description_for("coup", %{"turn_power" => {power, hero}}, _) do
    "Merciful blow! #{hero}'s [power]Power significantly increased by #{power}[/power] this turn"
  end

  # TODO: Remove later
  defp description_for("culling_blade", %{"extra" => {true, hero}}, heroes) do
    "#{hero} has been instantly executed by #{opponent_for(hero, heroes)}. [status]RIP[/status]"
  end

  defp description_for("culling_blade", %{"executed" => {true, hero}}, heroes) do
    "#{hero} has been instantly executed by #{opponent_for(hero, heroes)}. [status]RIP[/status]"
  end

  defp description_for("culling_blade", %{"damage" => {damage, hero}}, heroes) do
    "#{opponent_for(hero, heroes)} failed to do some basic math and dealt [damage]#{damage} damage[/damage] to #{hero}"
  end

  defp description_for("doom", %{"damage" => {damage, defender}, "silenced" => {true, _}}, _) do
    "Cursed to die, #{defender} took [damage]#{damage} damage[/damage] and [status]has been silenced[/status]"
  end

  defp description_for("dream_coil", %{"delayed_skill" => {_, hero}}, heroes) do
    "#{hero} created a coil of volatile magic near #{opponent_for(hero, heroes)}..."
  end

  defp description_for("dream_coil", %{"stunned" => {_, hero}, "damage" => {damage, _}}, _) do
    "#{hero} tried to run away from the coil and has been [status]stunned[/status], also taking [damage]#{damage} damage[/damage]"
  end

  defp description_for(
         "elder_dragon_form",
         %{"damage" => {damage, defender}, "turn_power" => {power, hero}, "hp_regen" => {regen, _}},
         _
       ) do
    "Now a majestic dragon, #{hero} gained [power]#{power} Power[/power] this turn and has [hp]regenerated #{regen}HP[/hp], also dealing [damage]#{
      damage
    } damage[/damage] to #{defender}"
  end

  defp description_for("gods_strength", %{"next_power_normal" => {power, attacker}}, _) do
    "Channeling immense rogue strength, #{attacker} will have an extra [power]#{power} Power[/power] for the two turns that deal Normal Damage"
  end

  defp description_for("guardian_angel", %{"hp_regen" => {regen, attacker}, "next_armor" => {armor, _}}, _) do
    "#{attacker} has been [status]#blessed[/status], [hp]regenerating #{regen} HP[/hp] and gaining [armor]#{armor} Armor[/armor]"
  end

  defp description_for("laguna_blade", %{"damage" => {damage, defender}}, heroes) do
    "Conjuring a beam of Pure energy, #{opponent_for(defender, heroes)} unleashed destruction on #{defender} dealing [damage]#{
      damage
    } damage[/damage]"
  end

  defp description_for("life_drain", %{"damage" => {damage, defender}, "hp_regen" => {regen, attacker}}, _) do
    "#{attacker} is channeling the vital essence out of #{defender}, dealing [damage]#{damage} damage[/damage] and [hp]regenerating #{
      regen
    } HP[/hp]"
  end

  defp description_for("life_drain", %{"damage" => {damage, defender}}, heroes) do
    "#{opponent_for(defender, heroes)} was abrutly interrupted while channeling the vital essence out of #{defender}, dealing [damage]#{
      damage
    } damage[/damage]"
  end

  defp description_for("omnislash", %{"damage" => {damage, defender}, "extra" => {true, attacker}}, _) do
    "#{attacker} decimated #{defender} with maximum slashes dealing [damage]#{damage} damage[/damage]"
  end

  defp description_for("omnislash", %{"damage" => {damage, defender}}, heroes) do
    "#{opponent_for(defender, heroes)} slashed #{defender} multiple times dealing [damage]#{damage} damage[/damage]"
  end

  defp description_for("psionic_trap", %{"permanent_skill" => {skill, hero}}, heroes) when skill == "psionic_trap" do
    "#{hero} set up a mystical trap near #{opponent_for(hero, heroes)}..."
  end

  defp description_for(
         "psionic_trap",
         %{"damage" => {damage, hero}, "turn_armor" => {armor, _}, "turn_atk" => {atk, _}},
         _
       ) do
    "#{hero} has been psyqued, taking [damage]#{damage} damage[/damage], losing [armor]#{armor * -1} armor[/armor] and [hp]#{
      atk * -1
    } ATK[/hp]"
  end

  defp description_for("rearm", %{"damage" => {damage, defender}, "spell_count" => {_, attacker}}, _) do
    "#{attacker} has no skill to reuse, dealing [damage]#{damage} damage[/damage] to #{defender}"
  end

  defp description_for("rearm", %{"bonus" => {skill, attacker}}, _) do
    "#{attacker} has reset all cooldowns and reused #{skill}"
  end

  defp description_for("remote_mines", %{"delayed_skill" => {_, hero}}, _) do
    "#{hero} planted an invisible mine..."
  end

  defp description_for("remote_mines", %{"damage" => {damage, defender}}, heroes) do
    "#{opponent_for(defender, heroes)} has detonated the mine, dealing [damage]#{damage} damage[/damage] to #{defender}"
  end

  defp description_for("spell_steal", %{"damage" => {damage, defender}}, heroes) do
    "#{opponent_for(defender, heroes)} has no skill to steal, dealing [damage]#{damage} damage[/damage] to #{defender}"
  end

  defp description_for("spell_steal", %{"turn_power" => {power, attacker}, "bonus" => {skill, _}}, heroes) do
    "#{attacker} has stolen #{skill} from #{opponent_for(attacker, heroes)} while also gaining an extra [power]#{power} Power[/power] for this turn and the next"
  end

  defp description_for("time_lapse", %{"damage" => {damage, defender}}, heroes) do
    "#{opponent_for(defender, heroes)} has jumped back in time, restoring its HP back to what it was last turn and dealing [damage]#{
      damage
    } damage[/damage] to #{defender}"
  end

  defp description_for("walrus_punch", %{"damage" => {damage, defender}}, heroes) do
    "#{opponent_for(defender, heroes)} launched #{defender} to the sky with a deadly punch, stunning and dealing [damage]#{
      damage
    } physical damage[/damage]"
  end

  # BOSS

  defp description_for("boss_slam", %{"damage" => {damage, defender}}, heroes) do
    "#{opponent_for(defender, heroes)} shattered the ground underneath, dealing [damage]#{damage} damage[/damage] to #{
      defender
    }"
  end

  defp description_for("boss_spell_block", %{"inneffectable" => {_, hero}}, _) do
    "#{hero} has blocked the effect of [status]stuns, silences and disarms[/status] this turn"
  end

  defp description_for("boss_bash", %{"stunned" => {_, hero}}, heroes) do
    "#{opponent_for(hero, heroes)} brutally smashed #{hero}, who has been [status]stunned[/status]"
  end

  defp description_for("boss_ult", %{"battle_armor" => {armor, hero}, "battle_power" => {power, _}}, _) do
    "Pulsating the essence of [status]The Immortal[/status], #{hero} gained [armor]#{armor} Armor[/armor] and [power]#{
      power
    } Power[/power] for the rest of the battle"
  end

  # ITEMS

  defp description_for("magic_stick", %{"hp_regen" => {hp, hero}, "mp_regen" => {mp, _}}, _) do
    "#{hero} regenerated [hp]#{hp} HP[/hp] and [mp]#{mp} MP[/mp] by activating the Magic Stick"
  end

  defp description_for("ring_of_tarrasque", %{"hp_regen" => {hp, hero}}, _) do
    "#{hero} regenerated [hp]#{hp} HP[/hp] from the soul of Tarrasque"
  end

  defp description_for("sages_mask", %{"mp_regen" => {mp, hero}}, _) do
    "#{hero} regenerated [mp]#{mp} MP[/mp] by wearing wisdom"
  end

  defp description_for("pipe_of_insight", %{"next_armor" => {armor, hero}}, _) do
    "Foreseeing damage, #{hero} created a magical barrier gaining [armor]#{armor} Armor[/armor] next turn"
  end

  defp description_for("shadow_blade", %{"damage" => {damage, hero}}, heroes) do
    "#{opponent_for(hero, heroes)} initiated the battle through the shadows, dealing [damage]#{damage} extra damage[/damage] to #{
      hero
    }"
  end

  defp description_for("silver_edge", %{"damage" => {damage, defender}, "extra" => {true, attacker}}, _) do
    "#{attacker} initiated the battle through the shadows by impaling #{defender} with the Edge, dealing [damage]#{
      damage
    } damage[/damage] this turn and [armor]reducing HP regeneration[/armor] for the next 2 turns"
  end

  defp description_for("silver_edge", %{"damage" => {damage, hero}}, heroes) do
    "#{opponent_for(hero, heroes)} initiated the battle through the shadows, dealing [damage]#{damage} extra damage[/damage] to #{
      hero
    }"
  end

  defp description_for("silver_edge", %{"extra" => {true, hero}}, heroes) do
    "#{hero} has impaled #{opponent_for(hero, heroes)} with the Edge, [damage]reducing HP regeneration[/damage] for the next 2 turns"
  end

  defp description_for("silver_edge", %{"hp_regen" => {regen, hero}}, heroes) do
    "#{opponent_for(hero, heroes)}'s Edge is still deep in the flesh of #{hero}, [damage]reducing HP regeneration by #{
      regen * -1
    }[/damage]"
  end

  defp description_for("tranquil_boots", %{"hp_regen" => {hp, hero}}, _) do
    "#{hero} regenerated [hp]#{hp} HP[/hp] through a mist of tranquility"
  end

  defp description_for("arcane_boots", %{"mp_regen" => {mp, hero}}, _) do
    "Drawing Arcane powers, #{hero} regenerated [mp]#{mp} MP[/mp]"
  end

  defp description_for("crystalys", %{"turn_power" => {power, hero}}, _) do
    "Critical hit! #{hero}'s [power]Power increased by #{power}[/power] this turn"
  end

  defp description_for("vanguard", %{"damage" => {damage, hero}}, _) do
    "#{hero}'s Vanguard blocked [armor]#{damage * -1} damage[/armor]"
  end

  defp description_for("dagon", %{"damage" => {damage, hero}}, heroes) do
    "#{opponent_for(hero, heroes)} blasted #{hero} for [damage]#{damage} damage[/damage]"
  end

  defp description_for("dagon5", %{"damage" => {damage, hero}}, heroes) do
    "#{opponent_for(hero, heroes)} blasted #{hero} for [damage]#{damage} damage[/damage]"
  end

  defp description_for("diffusal_blade", %{"mp_burn" => {mp, defender}, "damage" => {damage, _}}, heroes) do
    "#{opponent_for(defender, heroes)} has cut straight into #{defender}'s soul, burning [mp]#{mp} MP[/mp] and dealing [damage]#{
      damage
    } damage[/damage]"
  end

  defp description_for("assault_cuirass", %{"turn_armor" => {armor, hero}}, _) do
    "Affected by the Assault Aura, #{hero}'s [armor]Armor has been reduced by #{armor * -1}[/armor]"
  end

  defp description_for("maelstrom", %{"damage" => {damage, hero}}, _) do
    "The electrical storm radiating from Maelstrom dealt [damage]#{damage} damage[/damage] to #{hero}"
  end

  defp description_for("mkb", %{"invulnerable" => {_, hero}}, heroes) do
    "#{opponent_for(hero, heroes)}'s MKB activated, stopping #{hero} from becoming [status]invulnerable[/status] and [armor]nullifying their Armor[/armor] this turn"
  end

  defp description_for("bkb", %{"extra" => {true, hero}}, _) do
    "#{hero} activated BKB and will be [status]imune to stuns, silences and disarms[/status] for the next defending turn"
  end

  defp description_for("bkb", %{"inneffectable" => {_, hero}}, _) do
    "#{hero} is [status]imune to stuns, silences and disarms[/status] this turn"
  end

  defp description_for("linkens_sphere", %{"inneffectable" => {_, hero}}, _) do
    "#{hero} is [status]imune to stuns, silences and disarms[/status] this turn"
  end

  defp description_for("scythe_of_vyse", %{"stunned" => {_, hero}}, heroes) do
    "#{opponent_for(hero, heroes)} has hexed #{hero}, who is now [status]stunned[/status] on the next turn"
  end

  defp description_for("orchid_malevolence", %{"silenced" => {_, hero}, "turn_armor" => {armor, _}}, heroes) do
    "#{opponent_for(hero, heroes)} burned the soul of #{hero}, who has been [status]silenced[/status] and [armor]lost #{
      armor * -1
    } Armor[/armor] this turn"
  end

  defp description_for("shivas_guard", %{"next_armor" => {armor, hero}, "damage" => {damage, defender}}, _) do
    "A frozen blast has almost completely shielded #{hero}, who [armor]gained #{armor} Armor[/armor] next turn while also dealing [damage]#{
      damage
    } damage[/damage] to #{defender}"
  end

  defp description_for("satanic", %{"hp_regen" => {hp, hero}}, heroes) do
    "#{hero} has demonically regenerated [hp]#{round(hp)} HP[/hp] by stealing life from #{opponent_for(hero, heroes)}"
  end

  defp description_for("daedalus", %{"turn_power" => {power, hero}}, _) do
    "Massive critical hit! #{hero}'s [power]Power increased by #{power}[/power] this turn"
  end

  # EXTRAS

  defp description_for("disarmed", %{"extra" => {_, hero}}, _) do
    "#{hero} is [status]disarmed[/status] and cannot deal physical damage"
  end

  defp description_for("invulnerable", %{"extra" => {_, hero}}, _) do
    "#{hero} is [status]invulnerable[/status] and will take no damage this turn"
  end

  defp description_for(_, %{"stunned" => {_, hero}}, _) do
    "#{hero} has been [status]stunned[/status]"
  end

  defp description_for(_, %{"disarmed" => {_, hero}}, _) do
    "#{hero} has been [status]disarmed[/status] and will not deal physical damage next turn."
  end

  defp description_for("stunned", effects, _) do
    {_, hero} = hd(Map.values(effects))
    "#{hero} [status]is stunned[/status] and cannot attack this turn"
  end

  defp description_for("basic_attack", %{"damage" => {damage, hero}}, _) do
    "#{hero} took a punch in the face for [damage]#{damage} damage[/damage]"
  end

  defp description_for(resource, effects, _) do
    "Missing description for #{resource}. #{
      Enum.join(Enum.map(effects, fn {key, val} -> list_to_string(key, val) end), ", ")
    }"
  end

  defp list_to_string(key, val) when is_list(val) do
    Enum.map(val, fn item -> list_to_string(key, item) end)
    |> Enum.join(", ")
  end

  defp list_to_string(key, {val, hero}) do
    "#{key} - #{val} - #{hero}"
  end

  def opponent_for(hero, heroes) do
    if hero == heroes.attacker do
      heroes.defender
    else
      heroes.attacker
    end
  end
end
