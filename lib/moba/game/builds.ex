defmodule Moba.Game.Builds do
  @moduledoc """
  Manages Build records and queries.
  See Moba.Game.Schema.Build for more info.

  Also lists all builds used by bots and recommended starting builds (by role)
  """

  alias Moba.{Repo, Game}
  alias Game.Schema.Build
  alias Game.Query.SkillQuery

  # -------------------------------- PUBLIC API

  def get!(id) do
    Repo.get(Build, id) |> Repo.preload(skills: Game.ordered_skills_query())
  end

  def update!(build, attrs) do
    Build.changeset(build, attrs)
    |> Repo.update!()
  end

  @doc """
  When a Hero is picked for the Arena, it needs to have its Skills updated
  with the most recent values that may have been changed in the admin panel
  """
  def update_all_with_current_skills!(hero) do
    %{builds: builds} = Repo.preload(hero, builds: [:skills])

    builds =
      Enum.map(builds, fn build ->
        new_skills = Game.get_current_skills_from(build.skills)
        replace_skills!(build, new_skills)
      end)

    Map.put(hero, :builds, builds)
  end

  def replace_skills!(build, new_skills) do
    Build.replace_skills(build, new_skills)
    |> Repo.update!()
  end

  def create!(type, hero, skills, skill_order \\ nil, item_order \\ nil) do
    hero = Repo.preload(hero, [:items, avatar: [:ultimate]])
    skills = [hero.avatar.ultimate] ++ Enum.slice(skills, 0, 3)

    Build.create_changeset(
      %Build{},
      %{
        type: type,
        skill_order: skill_order || skills_to_order(skills),
        item_order: item_order || items_to_order(hero.items)
      },
      hero,
      skills
    )
    |> Repo.insert!()
  end

  @doc """
  Heroes can have up to 2 Builds, and this returns the one which is not
  currently active.
  """
  def other_build_for(%{active_build_id: active_build_id} = hero) do
    %{builds: builds} = Repo.preload(hero, builds: [skills: Game.ordered_skills_query()])

    other = Enum.find(builds, fn build -> build.id != active_build_id end)
    other || List.first(builds)
  end

  @doc """
  Grabs a pre-defined skill/item list and generates a build for a bot. These lists vary in effectiveness
  and strength depending on the difficulty and level. Weak bots have more random skills and less items, whilst
  strong bots have a proper skill build and a high tier inventory
  """
  def generate_for_bot!(bot) do
    lists = get_lists(bot)

    bot =
      Enum.reduce(lists.items, bot, fn item, acc ->
        Game.buy_item!(acc, item)
      end)

    create!("pve", bot, lists.skills, lists.skill_order, items_to_order(lists.items))
  end

  def skill_builds_for(role) do
    lists_for(role)
    |> codes_to_skills()
  end

  def skill_build_for(role, index) do
    skill_builds_for(role)
    |> Enum.at(index)
  end

  @doc """
  Resets the item_order for all of the Hero's builds when their inventory gets updated
  """
  def reset_item_orders!(%{items: items} = hero) do
    %{builds: builds} = Repo.preload(hero, :builds)

    updated_builds =
      Enum.map(builds, fn build ->
        update!(build, %{item_order: items_to_order(items)})
      end)

    Map.put(hero, :builds, updated_builds)
  end

  # --------------------------------

  defp get_lists(%{
         level: level,
         bot_difficulty: difficulty,
         total_farm: total_farm,
         avatar: %{code: code, ultimate_code: ultimate_code}
       }) do
    {skill_list, item_list, _} =
      lists_for(code)
      |> Enum.fetch!(Enum.random(0..1))

    skills = skills_list(skill_list, difficulty, ultimate_code)

    %{
      skills: skills,
      items: items_list(item_list, difficulty, level, total_farm),
      skill_order: skill_order(skill_list, skills, ultimate_code),
      item_order: item_list |> Enum.reverse()
    }
  end

  # random skill set depending on difficulty, the higher the difficulty the less random
  defp skills_list(skill_list, difficulty, ultimate_code) do
    skill_list = Enum.shuffle(skill_list -- [ultimate_code, "basic_attack"])

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
  defp items_list(item_list, difficulty, level, total_farm) do
    gold = extra_gold(difficulty, level, total_farm)

    {result, _} =
      case difficulty do
        "weak" -> item_list
        "moderate" -> Enum.shuffle(item_list)
        "strong" -> Enum.reverse(item_list)
      end
      |> Enum.map(fn item_code -> Game.get_item_by_code!(item_code) end)
      |> Enum.reduce({[], gold}, fn item, {items, remaining} ->
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
  # as possible. It's specially important that ultimates are used in the correct turn as well
  # as Basic Attacks in the case of builds that focus on that.
  # In a nutshell, we need to order skills to look as much like skill_list as possible
  defp skill_order(skill_list, skills, ultimate_code) do
    ult_index = Enum.find_index(skill_list, fn code -> code == ultimate_code end)
    basic_index = Enum.find_index(skill_list, fn code -> code == "basic_attack" end)
    clean_list = skill_list -- [ultimate_code, "basic_attack"]

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

    result = if ult_index, do: List.insert_at(result, ult_index, ultimate_code), else: result

    if basic_index, do: List.insert_at(result, basic_index, "basic_attack"), else: result
  end

  defp random_skills do
    SkillQuery.base_current()
    |> SkillQuery.normals()
    |> SkillQuery.with_level(1)
    |> SkillQuery.random()
    |> Repo.all()
  end

  defp extra_gold("strong", level, _) when level >= 25, do: 999_999
  defp extra_gold(_, _, total_farm), do: total_farm

  defp skills_to_order(skills) do
    skills |> Enum.filter(&(!&1.passive)) |> Enum.map(& &1.code)
  end

  defp items_to_order(items) do
    items |> Enum.filter(& &1.active) |> Enum.map(& &1.code)
  end

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

  defp lists_for(code) when code == "abaddon" do
    [
      {
        ["echo_stomp", "borrowed_time", "double_edge", "counter_helix"],
        ["maelstrom", "boots_of_travel", "assault_cuirass", "bkb", "linkens_sphere", "daedalus"],
        "Great damage skills for a longer fight. Echo Stomp requires more MP so we need a passive here."
      },
      {
        ["empower", "borrowed_time", "shuriken_toss", "double_edge"],
        ["maelstrom", "boots_of_travel", "bkb", "assault_cuirass", "daedalus", "orchid_malevolence"],
        "Less risky and more versatile, just make sure to rotate cooldowns effectively. Empower is great for longer fights."
      }
    ]
  end

  defp lists_for(code) when code == "axe" do
    [
      {
        ["static_link", "echo_stomp", "counter_helix", "culling_blade"],
        ["vanguard", "silver_edge", "assault_cuirass", "orchid_malevolence", "boots_of_travel", "daedalus"],
        "Balanced damage build."
      },
      {
        ["shuriken_toss", "double_edge", "counter_helix", "culling_blade"],
        ["maelstrom", "shivas_guard", "boots_of_travel", "linkens_sphere", "orchid_malevolence", "daedalus"],
        "More versatile if proper cooldown rotation is kept."
      }
    ]
  end

  defp lists_for(code) when code == "dazzle" do
    [
      {
        ["bad_juju", "echo_stomp", "shuriken_toss", "fiery_soul"],
        ["maelstrom", "boots_of_travel", "diffusal_blade", "dagon5", "orchid_malevolence", "daedalus"],
        "Your basic Carry build focused on Attack (ATK) skills to take advantage of Power provided by the ult."
      },
      {
        ["bad_juju", "illuminate", "fiery_soul", "lightning_bolt"],
        ["maelstrom", "linkens_sphere", "assault_cuirass", "scythe_of_vyse", "boots_of_travel", "daedalus"],
        "Full nuke build to take advantage of Power provided by the ult."
      }
    ]
  end

  defp lists_for(code) when code == "ddoom" do
    [
      {
        ["doom", "maledict", "lightning_bolt", "fiery_soul"],
        ["boots_of_travel", "dagon5", "assault_cuirass", "bkb", "orchid_malevolence", "scythe_of_vyse"],
        "Power nuker build for ending battles quickly."
      },
      {
        ["shadow_word", "doom", "illuminate", "mana_burn"],
        ["boots_of_travel", "dagon5", "assault_cuirass", "bkb", "linkens_sphere", "daedalus"],
        "Mixed damage build for a more sustained fight."
      }
    ]
  end

  defp lists_for(code) when code == "dragon_knight" do
    [
      {
        ["elder_dragon_form", "blade_fury", "double_edge", "fiery_soul"],
        ["shadow_blade", "boots_of_travel", "assault_cuirass", "silver_edge", "satanic", "daedalus"],
        "Power-focused Carry build"
      },
      {
        ["elder_dragon_form", "empower", "double_edge", "counter_helix"],
        ["maelstrom", "boots_of_travel", "shivas_guard", "linkens_sphere", "scythe_of_vyse", "daedalus"],
        "Low-cost attack skills focused on longer fights."
      }
    ]
  end

  defp lists_for(code) when code == "juggernaut" do
    [
      {
        ["omnislash", "blade_fury", "shuriken_toss", "fiery_soul"],
        ["tranquil_boots", "silver_edge", "assault_cuirass", "heavens_halberd", "satanic", "daedalus"],
        "Basic Power Carry build to quickly finish a battle."
      },
      {
        ["static_link", "omnislash", "blade_fury", "phase_shift"],
        ["maelstrom", "boots_of_travel", "assault_cuirass", "scythe_of_vyse", "linkens_sphere", "daedalus"],
        "A more defensive variant which may need extra Magic (MP) to function well."
      }
    ]
  end

  defp lists_for(code) when code == "lina" do
    [
      {
        ["empower", "maledict", "laguna_blade", "fiery_soul"],
        ["arcane_boots", "diffusal_blade", "assault_cuirass", "dagon5", "orchid_malevolence", "shivas_guard"],
        "Good balance of offense and defense with support for her ult by the use of Maledict. Will need Magic (MP) items to properly function."
      },
      {
        ["illuminate", "laguna_blade", "lightning_bolt", "fiery_soul"],
        ["vanguard", "boots_of_travel", "bkb", "diffusal_blade", "daedalus", "linkens_sphere"],
        "A more offensive Power Nuker variant."
      }
    ]
  end

  defp lists_for(code) when code == "phantom_assassin" do
    [
      {
        ["blink_strike", "feast", "jinada"],
        ["maelstrom", "assault_cuirass", "diffusal_blade", "orchid_malevolence", "silver_edge", "daedalus"],
        "Just enough Magic (MP) to cast Sweeping Blade whenever possible, with passives to support Basic Attacks."
      },
      {
        ["echo_stomp", "fury_swipes", "jinada"],
        ["shadow_blade", "diffusal_blade", "silver_edge", "linkens_sphere", "satanic", "daedalus"],
        "A more offensive variant with a strong Attack skill. Great damage if the ult activates on Echo Stomp."
      }
    ]
  end

  defp lists_for(code) when code == "puck" do
    [
      {
        ["dream_coil", "illuminate", "lightning_bolt", "phase_shift"],
        ["arcane_boots", "dagon5", "assault_cuirass", "shivas_guard", "orchid_malevolence", "scythe_of_vyse"],
        "Typical Nuker build, Maledict + Bolt after the ult is cast to take advantage of the stun can be quite effective."
      },
      {
        ["dream_coil", "echo_stomp", "phase_shift", "shuriken_toss"],
        ["maelstrom", "dagon", "heavens_halberd", "diffusal_blade", "orchid_malevolence", "linkens_sphere"],
        "More versatile Carry build with 3 actives that is made viable due to her extra MP. Make sure to cast Echo Stomp right after the ult."
      }
    ]
  end

  defp lists_for(code) when code == "pugna" do
    [
      {
        ["double_edge", "empower", "life_drain", "fiery_soul"],
        ["vanguard", "boots_of_travel", "diffusal_blade", "satanic", "linkens_sphere", "shivas_guard"],
        "Basic carry build with strong regenration."
      },
      {
        ["maledict", "life_drain", "phase_shift", "lightning_bolt"],
        ["maelstrom", "boots_of_travel", "orchid_malevolence", "satanic", "dagon5", "scythe_of_vyse"],
        "Extreme Nuker build for full on destruction."
      }
    ]
  end

  defp lists_for(code) when code == "omniknight" do
    [
      {
        ["guardian_angel", "double_edge", "counter_helix", "shuriken_toss"],
        ["maelstrom", "boots_of_travel", "diffusal_blade", "dagon5", "orchid_malevolence", "daedalus"],
        "Single turn damage focused build."
      },
      {
        ["double_edge", "guardian_angel", "echo_stomp", "fiery_soul"],
        ["maelstrom", "boots_of_travel", "daedalus", "scythe_of_vyse", "linkens_sphere", "orchid_malevolence"],
        "A more offensive Carry variant."
      }
    ]
  end

  defp lists_for(code) when code == "rubick" do
    [
      {
        ["maledict", "spell_steal", "lightning_bolt", "death_pulse"],
        ["tranquil_boots", "diffusal_blade", "bkb", "dagon5", "shivas_guard", "daedalus"],
        "Full Nuker with great damage output. May need some Magic (MP) items to be viable."
      },
      {
        ["maledict", "spell_steal", "mana_shield", "fiery_soul"],
        ["vanguard", "dagon", "boots_of_travel", "linkens_sphere", "shivas_guard", "daedalus"],
        "A more low-cost Power-focused variant."
      }
    ]
  end

  defp lists_for(code) when code == "sniper" do
    [
      {
        ["static_link", "assassinate", "blade_fury", "phase_shift"],
        ["maelstrom", "bkb", "assault_cuirass", "boots_of_travel", "satanic", "silver_edge"],
        "A more defensive build to guarantee survival after the ult is cast."
      },
      {
        ["empower", "assassinate", "decay", "phase_shift"],
        ["vanguard", "boots_of_travel", "diffusal_blade", "scythe_of_vyse", "shivas_guard", "daedalus"],
        "An offensive variant that empowers the ult and provides some regeneration."
      }
    ]
  end

  defp lists_for(code) when code == "sven" do
    [
      {
        ["gods_strength", "basic_attack", "fury_swipes", "feast", "jinada"],
        ["maelstrom", "boots_of_travel", "diffusal_blade", "orchid_malevolence", "linkens_sphere", "daedalus"],
        "Full passives to support Basic Attacks."
      },
      {
        ["double_edge", "gods_strength", "basic_attack", "fury_swipes", "counter_helix"],
        ["vanguard", "boots_of_travel", "bkb", "shivas_guard", "satanic", "daedalus"],
        "A more offensive variant completely focused on damage output."
      }
    ]
  end

  defp lists_for(code) when code == "techies" do
    [
      {
        ["remote_mines", "lightning_bolt", "mana_shield", "death_pulse"],
        ["maelstrom", "boots_of_travel", "diffusal_blade", "dagon5", "orchid_malevolence", "daedalus"],
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
        ["psionic_trap", "blink_strike", "decay", "fiery_soul"],
        ["maelstrom", "boots_of_travel", "silver_edge", "scythe_of_vyse", "linkens_sphere", "daedalus"],
        "Balanced build for constant spellcasting."
      },
      {
        ["psionic_trap", "maledict", "lightning_bolt", "counter_helix"],
        ["vanguard", "boots_of_travel", "heavens_halberd", "diffusal_blade", "shivas_guard", "daedalus"],
        "A more offensive Nuker variant."
      }
    ]
  end

  defp lists_for(code) when code == "tinker" do
    [
      {
        ["maledict", "rearm", "lightning_bolt", "mana_shield"],
        ["maelstrom", "boots_of_travel", "assault_cuirass", "dagon5", "scythe_of_vyse", "daedalus"],
        "Full on offensive Nuker."
      },
      {
        ["shadow_word", "rearm", "death_pulse", "mana_burn"],
        ["vanguard", "boots_of_travel", "assault_cuirass", "dagon5", "orchid_malevolence", "linkens_sphere"],
        "A more balanced variant with sustained damage and constant regeneration."
      }
    ]
  end

  defp lists_for(code) when code == "troll_warlord" do
    [
      {
        ["decay", "double_edge", "empower"],
        ["tranquil_boots", "diffusal_blade", "assault_cuirass", "linkens_sphere", "satanic", "daedalus"],
        "Low-cost offensive build with some regeneration to handle longer fights."
      },
      {
        ["feast", "fury_swipes", "jinada"],
        ["vanguard", "boots_of_travel", "bkb", "shivas_guard", "assault_cuirass", "daedalus"],
        "Full Basic Attack variant."
      }
    ]
  end

  defp lists_for(code) when code == "tusk" do
    [
      {
        ["walrus_punch", "jinada", "fury_swipes", "feast"],
        ["maelstrom", "boots_of_travel", "assault_cuirass", "orchid_malevolence", "linkens_sphere", "daedalus"],
        "Full physical damage build to support his ultimate."
      },
      {
        ["shuriken_toss", "walrus_punch", "fury_swipes", "jinada"],
        ["vanguard", "boots_of_travel", "bkb", "shivas_guard", "orchid_malevolence", "daedalus"],
        "A more offensive variant that can be effective against opponents with high Armor."
      }
    ]
  end

  defp lists_for(code) when code == "weaver" do
    [
      {
        ["echo_stomp", "time_lapse", "shuriken_toss", "fiery_soul"],
        ["maelstrom", "boots_of_travel", "assault_cuirass", "scythe_of_vyse", "linkens_sphere", "daedalus"],
        "Large damage output to take maximum advange of the ult."
      },
      {
        ["blink_strike", "time_lapse", "phase_shift", "fiery_soul"],
        ["tranquil_boots", "diffusal_blade", "assault_cuirass", "dagon5", "satanic", "daedalus"],
        "Basic Power Carry build to quickly finish a battle."
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
