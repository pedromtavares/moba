defmodule Moba.Game.Builds do
  @moduledoc """
  Lists all builds used by bots and recommended starting builds (by role)
  """

  alias Moba.{Repo, Game}
  alias Game.Query.SkillQuery

  # -------------------------------- PUBLIC API

  @doc """
  Grabs a pre-defined skill/item list for a bot. These lists vary in effectiveness
  and strength depending on the difficulty and level. Weak bots have more random skills and less items, whilst
  strong bots have a proper skill build and a high tier inventory
  """
  def generate_bot_build(
        %{level: level, bot_difficulty: difficulty, total_gold_farm: total_gold_farm},
        %{code: code, ultimate_code: ultimate_code}
      ) do
    {skill_list, item_list, _} = lists_for(code) |> Enum.fetch!(Enum.random(0..1))

    skills = skills_list(skill_list, difficulty, ultimate_code)

    %{
      skills: skills,
      items: items_list(item_list, difficulty, level, total_gold_farm),
      skill_order: skill_order(skill_list, skills, ultimate_code),
      item_order: Enum.reverse(item_list)
    }
  end

  def skill_builds_for(role), do: lists_for(role) |> codes_to_skills()

  def skill_build_for(role, index), do: skill_builds_for(role) |> Enum.at(index)

  # --------------------------------

  # random skill set depending on difficulty, the higher the difficulty the less random
  defp skills_list(skill_list, difficulty, ultimate_code) do
    skill_list = Enum.shuffle(skill_list -- [ultimate_code])

    skills =
      case difficulty do
        "weak" -> Enum.take(skill_list, 1)
        "moderate" -> Enum.take(skill_list, 2)
        _ -> if(Enum.random(0..1) > 0, do: skill_list, else: Enum.take(skill_list, 2))
      end
      |> Enum.map(fn skill -> Game.get_current_skill!(skill) end)

    (skills ++ random_skills())
    |> Enum.uniq_by(fn skill -> skill.id end)
    |> Enum.take(3)
  end

  # item lists go from weak -> strong, so weak bots get this list as is and stronger bots reverse it,
  # first buying stronger items, making them much more challenging at any level
  defp items_list(item_list, difficulty, level, total_gold_farm) do
    {result, _} =
      case items_difficulty(difficulty, level) do
        "weak" -> item_list ++ random_rares() ++ random_normals()
        "moderate" -> Enum.shuffle(item_list) ++ random_rares() ++ random_normals()
        "strong" -> Enum.reverse(item_list) ++ random_rares() ++ random_normals()
        "pvp_master" -> Enum.reverse(item_list)
        "pvp_grandmaster" -> random_legendaries() ++ random_epics()
      end
      |> Enum.map(fn item_code -> Game.get_item_by_code!(item_code) end)
      |> Enum.take(6)
      |> Enum.reduce({[], total_gold_farm}, fn item, {items, remaining} ->
        price = Game.item_price(item)

        if remaining >= price do
          {items ++ [item], remaining - price}
        else
          {items, remaining}
        end
      end)

    result
  end

  # Since skill lists get randomized sometimes, we need to do some handling to make sure
  # that whatever wasn't randomized stays in the same order, so that bots can be as effective
  # as possible. It's specially important that ultimates are used in the correct turn as well.
  # In a nutshell, we need to order skills to look as much like skill_list as possible
  defp skill_order(skill_list, skills, ultimate_code) do
    ult_index = Enum.find_index(skill_list, fn code -> code == ultimate_code end)
    clean_list = skill_list -- [ultimate_code]

    skill_codes =
      skills
      |> Enum.filter(fn skill -> !skill.passive end)
      |> Enum.map(fn skill -> skill.code end)

    indexes =
      skill_codes
      |> Enum.map(fn skill_code ->
        {skill_code, Enum.find_index(clean_list, fn list_code -> list_code == skill_code end)}
      end)

    no_passives_list =
      clean_list
      |> Enum.map(fn code -> Game.get_current_skill!(code) end)
      |> Enum.filter(fn skill -> !skill.passive end)
      |> Enum.map(fn skill -> skill.code end)

    result = skill_codes -- no_passives_list

    result =
      Enum.reduce(indexes, result, fn {code, index}, acc ->
        if index, do: List.insert_at(acc, index, code), else: acc
      end)

    if ult_index, do: List.insert_at(result, ult_index, ultimate_code), else: result
  end

  defp random_skills do
    SkillQuery.base_current()
    |> SkillQuery.normals()
    |> SkillQuery.with_level(1)
    |> SkillQuery.random()
    |> Repo.all()
  end

  defp random_epics do
    ["diffusal_blade", "heavens_halberd", "assault_cuirass"] |> Enum.shuffle()
  end

  defp random_legendaries do
    [
      "silver_edge",
      "dagon5",
      "linkens_sphere",
      "boots_of_travel",
      "orchid_malevolence",
      "shivas_guard",
      "scythe_of_vyse",
      "daedalus",
      "satanic"
    ]
    |> Enum.shuffle()
    |> Enum.take(6)
  end

  defp random_normals do
    ["magic_stick", "sages_mask", "blades_of_attack", "ring_of_tarrasque", "chainmail"] |> Enum.shuffle()
  end

  defp random_rares do
    ["maelstrom", "shadow_blade", "vanguard", "pipe_of_insight"]
  end

  defp items_difficulty("strong", level) when level > 27, do: "pvp_grandmaster"
  defp items_difficulty(difficulty, _), do: difficulty

  defp codes_to_skills(lists) do
    lists
    |> Enum.map(fn {list, desc} ->
      {
        Enum.map(list, fn skill_code ->
          Game.get_current_skill!(skill_code)
        end),
        desc
      }
    end)
  end

  # ROLES

  defp lists_for(code) when code == "tank" do
    [
      {
        ["empower", "double_edge", "counter_helix"],
        "Balanced Tank"
      },
      {
        ["double_edge", "decay", "counter_helix"],
        "Regenerator"
      },
      {
        ["empower", "double_edge", "shuriken_toss"],
        "Power Carry"
      }
    ]
  end

  defp lists_for(code) when code == "bruiser" do
    [
      {
        ["empower", "double_edge", "decay"],
        "Balanced Bruiser"
      },
      {
        ["double_edge", "decay", "fiery_soul"],
        "Versatile Bruiser"
      },
      {
        ["empower", "double_edge", "fiery_soul"],
        "Full Power"
      }
    ]
  end

  defp lists_for(code) when code == "carry" do
    [
      {
        ["blink_strike", "decay", "fiery_soul"],
        "Blink Striker"
      },
      {
        ["blade_fury", "shuriken_toss", "fiery_soul"],
        "Power Carry"
      },
      {
        ["empower", "blade_fury", "fiery_soul"],
        "Furious Blade"
      }
    ]
  end

  defp lists_for(code) when code == "nuker" do
    [
      {
        ["maledict", "lightning_bolt", "death_pulse"],
        "Versatile Nuker"
      },
      {
        ["mana_burn", "maledict", "lightning_bolt"],
        "Extreme Nuker"
      },
      {
        ["empower", "shuriken_toss", "mana_burn"],
        "Magic Ninja"
      }
    ]
  end

  defp lists_for(code) when code == "support" do
    [
      {
        ["blade_fury", "shuriken_toss", "fiery_soul"],
        "Furious Blade"
      },
      {
        ["mana_burn", "maledict", "lightning_bolt"],
        "Extreme Nuker"
      },
      {
        ["empower", "double_edge", "lightning_bolt"],
        "Lethal Support"
      }
    ]
  end

  # HEROES

  defp lists_for(code) when code == "abaddon" do
    [
      {
        ["empower", "borrowed_time", "fury_swipes", "jinada"],
        ["maelstrom", "heavens_halberd", "orchid_malevolence", "satanic", "linkens_sphere", "daedalus"],
        "custom"
      },
      {
        ["double_edge", "borrowed_time", "decay", "fiery_soul"],
        ["maelstrom", "diffusal_blade", "assault_cuirass", "shivas_guard", "daedalus", "orchid_malevolence"],
        "blueshyguy"
      }
    ]
  end

  defp lists_for(code) when code == "axe" do
    [
      {
        ["static_link", "double_edge", "counter_helix", "culling_blade"],
        ["vanguard", "satanic", "assault_cuirass", "orchid_malevolence", "shivas_guard", "daedalus"],
        "custom"
      },
      {
        ["shuriken_toss", "decay", "jinada", "culling_blade"],
        ["maelstrom", "shivas_guard", "boots_of_travel", "linkens_sphere", "orchid_malevolence", "daedalus"],
        "custom"
      }
    ]
  end

  defp lists_for(code) when code == "dazzle" do
    [
      {
        ["bad_juju", "decay", "lightning_bolt", "fiery_soul"],
        ["maelstrom", "satanic", "silver_edge", "boots_of_travel", "shivas_guard", "daedalus"],
        "custom"
      },
      {
        ["bad_juju", "decay", "illuminate", "fiery_soul"],
        ["maelstrom", "linkens_sphere", "assault_cuirass", "dagon5", "shivas_guard", "daedalus"],
        "3x3one"
      }
    ]
  end

  defp lists_for(code) when code == "ddoom" do
    [
      {
        ["doom", "death_pulse", "counter_helix", "fiery_soul"],
        ["boots_of_travel", "dagon5", "shivas_guard", "bkb", "satanic", "scythe_of_vyse"],
        "mantwi"
      },
      {
        ["doom", "death_pulse", "mana_burn", "phase_shift"],
        ["silver_edge", "dagon5", "assault_cuirass", "bkb", "linkens_sphere", "daedalus"],
        ""
      }
    ]
  end

  defp lists_for(code) when code == "dragon_knight" do
    [
      {
        ["elder_dragon_form", "decay", "feast", "jinada"],
        ["shadow_blade", "boots_of_travel", "assault_cuirass", "silver_edge", "satanic", "daedalus"],
        "matheusdsm"
      },
      {
        ["elder_dragon_form", "echo_stomp", "fury_swipes", "jinada"],
        ["maelstrom", "shivas_guard", "linkens_sphere", "satanic", "daedalus", "silver_edge"],
        "casualPlayer"
      }
    ]
  end

  defp lists_for(code) when code == "juggernaut" do
    [
      {
        ["static_link", "omnislash", "feast", "jinada"],
        ["tranquil_boots", "assault_cuirass", "shivas_guard", "orchid_malevolence", "satanic", "daedalus"],
        "Joj667"
      },
      {
        ["omnislash", "decay", "blade_fury", "jinada"],
        ["maelstrom", "silver_edge", "assault_cuirass", "orchid_malevolence", "linkens_sphere", "daedalus"],
        ""
      }
    ]
  end

  defp lists_for(code) when code == "lina" do
    [
      {
        ["maledict", "laguna_blade", "decay", "fiery_soul"],
        ["arcane_boots", "assault_cuirass", "satanic", "dagon5", "silver_edge", "shivas_guard"],
        "casualPlayer"
      },
      {
        ["maledict", "laguna_blade", "phase_shift", "fiery_soul"],
        ["vanguard", "boots_of_travel", "orchid_malevolence", "silver_edge", "daedalus", "linkens_sphere"],
        ""
      }
    ]
  end

  defp lists_for(code) when code == "phantom_assassin" do
    [
      {
        ["static_link", "decay", "jinada"],
        ["maelstrom", "assault_cuirass", "silver_edge", "linkens_sphere", "shivas_guard", "daedalus"],
        "Joj667"
      },
      {
        ["decay", "feast", "jinada"],
        ["tranquil_boots", "diffusal_blade", "silver_edge", "orchid_malevolence", "satanic", "daedalus"],
        "mantwi"
      }
    ]
  end

  defp lists_for(code) when code == "puck" do
    [
      {
        ["dream_coil", "illuminate", "lightning_bolt", "phase_shift"],
        ["arcane_boots", "dagon5", "linkens_sphere", "shivas_guard", "orchid_malevolence", "scythe_of_vyse"],
        "Typical Nuker build, Maledict + Bolt after the ult is cast to take advantage of the stun can be quite effective."
      },
      {
        ["dream_coil", "mana_burn", "phase_shift", "death_pulse"],
        ["maelstrom", "dagon5", "silver_edge", "assault_cuirass", "orchid_malevolence", "linkens_sphere"],
        "More versatile Carry build with 3 actives that is made viable due to her extra MP. Make sure to cast Echo Stomp right after the ult."
      }
    ]
  end

  defp lists_for(code) when code == "pugna" do
    [
      {
        ["life_drain", "mana_burn", "lightning_bolt", "phase_shift"],
        ["vanguard", "dagon5", "diffusal_blade", "silver_edge", "linkens_sphere", "shivas_guard"],
        "custom"
      },
      {
        ["life_drain", "illuminate", "mana_shield", "fiery_soul"],
        ["maelstrom", "heavens_halberd", "linkens_sphere", "satanic", "dagon5", "shivas_guard"],
        "PDK"
      }
    ]
  end

  defp lists_for(code) when code == "omniknight" do
    [
      {
        ["blade_fury", "guardian_angel", "decay", "feast"],
        ["maelstrom", "assault_cuirass", "daedalus", "satanic", "diffusal_blade", "shivas_guard"],
        "matheusdsm"
      },
      {
        ["echo_stomp", "guardian_angel", "fury_swipes", "jinada"],
        ["maelstrom", "daedalus", "satanic", "boots_of_travel", "silver_edge", "linkens_sphere"],
        "casualPlayer"
      }
    ]
  end

  defp lists_for(code) when code == "rubick" do
    [
      {
        ["spell_steal", "empower", "echo_stomp", "fiery_soul"],
        ["tranquil_boots", "diffusal_blade", "heavens_halberd", "satanic", "shivas_guard", "daedalus"],
        "casualPlayer"
      },
      {
        ["spell_steal", "maledict", "lightning_bolt", "counter_helix"],
        ["vanguard", "dagon", "satanic", "linkens_sphere", "shivas_guard", "daedalus"],
        "Asura"
      }
    ]
  end

  defp lists_for(code) when code == "sniper" do
    [
      {
        ["assassinate", "static_link", "feast", "jinada"],
        ["maelstrom", "assault_cuirass", "silver_edge", "linkens_sphere", "daedalus", "shivas_guard"],
        "matheusdsm"
      },
      {
        ["assassinate", "decay", "fury_swipes", "jinada"],
        ["vanguard", "diffusal_blade", "linkens_sphere", "silver_edge", "satanic", "shivas_guard"],
        "Joj667"
      }
    ]
  end

  defp lists_for(code) when code == "sven" do
    [
      {
        ["gods_strength", "decay", "feast", "jinada"],
        ["maelstrom", "boots_of_travel", "silver_edge", "orchid_malevolence", "linkens_sphere", "daedalus"],
        "matheusdsm"
      },
      {
        ["gods_strength", "decay", "double_edge", "fiery_soul"],
        ["vanguard", "boots_of_travel", "diffusal_blade", "shivas_guard", "satanic", "daedalus"],
        "blueshyguy"
      }
    ]
  end

  defp lists_for(code) when code == "techies" do
    [
      {
        ["remote_mines", "lightning_bolt", "mana_shield", "death_pulse"],
        ["maelstrom", "boots_of_travel", "silver_edge", "dagon5", "orchid_malevolence", "daedalus"],
        "Sustained damage build for longer fights."
      },
      {
        ["remote_mines", "lightning_bolt", "mana_burn", "phase_shift"],
        ["vanguard", "boots_of_travel", "dagon5", "linkens_sphere", "scythe_of_vyse", "orchid_malevolence"],
        "Balanced Nuker build: damage, regeneration and disable."
      }
    ]
  end

  defp lists_for(code) when code == "templar_assassin" do
    [
      {
        ["psionic_trap", "decay", "empower", "lightning_bolt"],
        ["maelstrom", "shivas_guard", "silver_edge", "satanic", "linkens_sphere", "daedalus"],
        "PDK"
      },
      {
        ["psionic_trap", "lightning_bolt", "blade_fury", "fiery_soul"],
        ["diffusal_blade", "dagon5", "satanic", "linkens_sphere", "shivas_guard", "daedalus"],
        "Atsuki"
      }
    ]
  end

  defp lists_for(code) when code == "tinker" do
    [
      {
        ["lightning_bolt", "rearm", "death_pulse", "mana_shield"],
        ["maelstrom", "boots_of_travel", "satanic", "dagon5", "scythe_of_vyse", "daedalus"],
        "Atsuki"
      },
      {
        ["mana_burn", "rearm", "mana_shield", "fiery_soul"],
        ["vanguard", "boots_of_travel", "scythe_of_vyse", "satanic", "shivas_guard", "linkens_sphere"],
        "custom"
      }
    ]
  end

  defp lists_for(code) when code == "troll_warlord" do
    [
      {
        ["static_link", "decay", "jinada"],
        ["tranquil_boots", "assault_cuirass", "shivas_guard", "linkens_sphere", "satanic", "daedalus"],
        "PDK"
      },
      {
        ["feast", "jinada", "phase_shift"],
        ["shadow_blade", "boots_of_travel", "assault_cuirass", "satanic", "shivas_guard", "daedalus"],
        "ererer"
      }
    ]
  end

  defp lists_for(code) when code == "tusk" do
    [
      {
        ["walrus_punch", "decay", "fury_swipes", "jinada"],
        ["maelstrom", "assault_cuirass", "satanic", "shivas_guard", "linkens_sphere", "daedalus"],
        "casualPlayer"
      },
      {
        ["shuriken_toss", "walrus_punch", "fury_swipes", "jinada"],
        ["vanguard", "boots_of_travel", "silver_edge", "shivas_guard", "orchid_malevolence", "daedalus"],
        ""
      }
    ]
  end

  defp lists_for(code) when code == "weaver" do
    [
      {
        ["empower", "time_lapse", "blade_fury", "fiery_soul"],
        ["maelstrom", "boots_of_travel", "assault_cuirass", "satanic", "linkens_sphere", "daedalus"],
        "Pestilence"
      },
      {
        ["echo_stomp", "time_lapse", "fury_swipes", "jinada"],
        ["tranquil_boots", "silver_edge", "assault_cuirass", "satanic", "dagon5", "daedalus"],
        "Atsuki"
      }
    ]
  end

  defp lists_for(_) do
    [
      {
        ["decay", "shuriken_toss", "fiery_soul"],
        ["shadow_blade", "heavens_halberd", "bkb", "maelstrom", "daedalus", "orchid_malevolence"],
        ""
      },
      {
        ["death_pulse", "shuriken_toss", "fiery_soul"],
        ["shadow_blade", "heavens_halberd", "bkb", "maelstrom", "daedalus", "orchid_malevolence"],
        ""
      }
    ]
  end
end
