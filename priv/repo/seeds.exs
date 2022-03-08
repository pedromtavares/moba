# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Moba.Repo.insert!(%Moba.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Moba.{Repo, Game, Accounts, Admin}
alias Game.Schema.{Item, Skill, Avatar, Quest}
alias Accounts.Schema.User

defmodule SeedHelper do
  def create_bot(bot_tier, avatar_codes) do
    name = Faker.Superhero.name()
    email = Faker.Internet.email()

    season_points =
      case bot_tier do
        4 -> 200..499
        5 -> 500..999
        6 -> 1000..3999
        _ -> 0..199
      end
      |> Enum.random()

    season_tier = Accounts.season_tier_for(season_points)

    case Admin.create_user(%{
           username: name,
           email: email,
           is_bot: true,
           bot_tier: bot_tier,
           season_points: season_points,
           season_tier: season_tier,
           bot_codes: avatar_codes
         }) do
      {:ok, user} -> user
      {:error, _} -> create_bot(bot_tier, avatar_codes)
    end
  end

  def create_pvp_bots do
    codes = Game.list_avatars() |> Enum.map(& &1.code)

    # creates 10 plat and 10 diamond bots, each with 2 avatar codes
    Enum.each(3..4, fn bot_tier ->
      Enum.reduce(1..10, codes, fn _, acc ->
        used = Enum.shuffle(acc) |> Enum.take(2)
        create_bot(bot_tier, used)
        acc -- used
      end)
    end)

    # creates 40 master bots, each with 3 avatar codes
    Enum.reduce(1..40, codes, fn _, acc ->
      used = Enum.shuffle(acc) |> Enum.take(3)
      total = length(used)

      if total < 3 do
        new_acc = acc ++ Enum.shuffle(codes)
        used = used ++ Enum.take(new_acc, 3 - total)
        create_bot(5, used)
        new_acc -- used
      else
        create_bot(5, used)
        acc -- used
      end
    end)

    # creates 40 grandmaster bots, each with 4 avatar coces
    Enum.reduce(1..40, codes, fn _, acc ->
      used = Enum.shuffle(acc) |> Enum.take(4)
      total = length(used)

      if total < 4 do
        new_acc = acc ++ Enum.shuffle(codes)
        used = used ++ Enum.take(new_acc, 4 - total)
        create_bot(6, used)
        new_acc -- used
      else
        create_bot(6, used)
        acc -- used
      end
    end)
  end

  def image_for(code) do
    %Plug.Upload{filename: "#{code}.png", path: "priv/resources/#{code}.png", content_type: "image/png"}
  end

  def create_item(attrs) do
    Repo.insert!(Item.changeset(%Item{}, attrs_with_image(attrs)))
  end

  def create_skill(attrs) do
    Repo.insert!(Skill.changeset(%Skill{}, attrs_with_image(attrs)))
  end

  def create_avatar(attrs) do
    Repo.insert!(Avatar.create_changeset(%Avatar{}, attrs_with_image(attrs), attrs[:ultimate], nil))
  end

  def attrs_with_image(attrs) do
    unless System.get_env("GITHUB_ACTIONS") do
      Map.merge(attrs, %{image: image_for(attrs[:code]), background: image_for(attrs[:code])})
    else
      attrs
    end
  end
end

%User{is_admin: true, tutorial_step: 0, shard_count: 100, level: 20}
|> User.changeset(%{
  email: "admin@browsermoba.com",
  username: "Admin",
  password: "123456",
  password_confirmation: "123456"
})
|> Repo.insert!()

# ITEMS

SeedHelper.create_item(%{
  code: "boots_of_speed",
  name: "Boots of Speed",
  mp_cost: 0,
  rarity: "normal",
  base_speed: 20
})

SeedHelper.create_item(%{
  code: "tranquil_boots",
  name: "Tranquil Boots",
  mp_cost: 5,
  rarity: "rare",
  base_amount: 80,
  base_speed: 30,
  active: true,
  cooldown: 3
})

SeedHelper.create_item(%{
  code: "arcane_boots",
  name: "Arcane Boots",
  base_speed: 30,
  base_amount: 20,
  active: true,
  cooldown: 3,
  rarity: "rare"
})

SeedHelper.create_item(%{
  code: "phase_boots",
  name: "Phase Boots",
  rarity: "epic",
  base_speed: 40,
  base_atk: 10
})

SeedHelper.create_item(%{
  code: "boots_of_travel",
  name: "Boots of Travel",
  rarity: "legendary",
  base_speed: 50,
  base_power: 15
})

SeedHelper.create_item(%{
  code: "blades_of_attack",
  name: "Blades of Attack",
  rarity: "normal",
  base_atk: 5
})

SeedHelper.create_item(%{
  code: "chainmail",
  name: "Chainmail",
  rarity: "normal",
  base_armor: 10
})

SeedHelper.create_item(%{
  code: "sages_mask",
  name: "Sage's Mask",
  rarity: "normal",
  base_mp: 10,
  base_amount: 5,
  passive: true
})

SeedHelper.create_item(%{
  code: "ring_of_tarrasque",
  name: "Ring of Tarrasque",
  rarity: "normal",
  base_hp: 20,
  base_amount: 7,
  passive: true
})

SeedHelper.create_item(%{
  code: "magic_stick",
  name: "Magic Stick",
  rarity: "normal",
  base_amount: 5,
  extra_amount: 5,
  active: true,
  cooldown: 0,
  mp_cost: 0
})

SeedHelper.create_item(%{
  code: "pipe_of_insight",
  name: "Pipe of Insight",
  base_hp: 35,
  active: true,
  cooldown: 3,
  rarity: "rare",
  armor_amount: 25
})

SeedHelper.create_item(%{
  code: "shadow_blade",
  name: "Shadow Blade",
  base_amount: 15,
  rarity: "rare",
  base_hp: 11,
  base_mp: 6,
  base_atk: 2,
  passive: true
})

SeedHelper.create_item(%{
  code: "vanguard",
  name: "Vanguard",
  extra_amount: 10,
  roll_number: 30,
  rarity: "rare",
  base_hp: 21,
  base_mp: 6,
  passive: true
})

SeedHelper.create_item(%{
  code: "maelstrom",
  name: "Maelstrom",
  base_atk: 14,
  base_amount: 30,
  rarity: "rare",
  passive: true
})

SeedHelper.create_item(%{
  code: "assault_cuirass",
  name: "Assault Cuirass",
  armor_amount: 25,
  base_hp: 15,
  base_atk: 2,
  base_armor: 20,
  rarity: "epic",
  passive: true
})

SeedHelper.create_item(%{
  code: "dagon",
  name: "Dagon",
  base_hp: 30,
  base_mp: 17,
  active: true,
  mp_cost: 5,
  cooldown: 3,
  rarity: "epic",
  base_amount: 30
})

SeedHelper.create_item(%{
  code: "bkb",
  name: "Black King Bar",
  roll_number: 60,
  base_hp: 66,
  base_atk: 8,
  rarity: "epic",
  active: true,
  cooldown: 3,
  duration: 2
})

SeedHelper.create_item(%{
  code: "diffusal_blade",
  name: "Diffusal Blade",
  base_atk: 18,
  mp_multiplier: 0.06,
  other_mp_multiplier: 0.06,
  cooldown: 3,
  rarity: "epic",
  passive: true
})

SeedHelper.create_item(%{
  code: "daedalus",
  name: "Daedalus",
  roll_number: 25,
  power_amount: 50,
  base_atk: 21,
  rarity: "legendary",
  passive: true
})

SeedHelper.create_item(%{
  code: "orchid_malevolence",
  name: "Orchid Malevolence",
  armor_amount: 30,
  base_hp: 12,
  base_mp: 5,
  base_atk: 2,
  rarity: "legendary"
})

SeedHelper.create_item(%{
  code: "heavens_halberd",
  name: "Heaven's Halberd",
  roll_number: 30,
  base_hp: 30,
  base_mp: 20,
  base_atk: 6,
  active: true,
  rarity: "epic"
})

SeedHelper.create_item(%{
  code: "satanic",
  name: "Satanic",
  base_atk: 11,
  base_hp: 50,
  active: true,
  hp_regen_multiplier: 0.65,
  cooldown: 3,
  rarity: "legendary"
})

SeedHelper.create_item(%{
  code: "scythe_of_vyse",
  name: "Scythe of Vyse",
  base_hp: 10,
  base_mp: 40,
  active: true,
  cooldown: 3,
  rarity: "legendary"
})

SeedHelper.create_item(%{
  code: "shivas_guard",
  name: "Shivas's Guard",
  base_hp: 22,
  base_mp: 25,
  base_atk: 5,
  armor_amount: 200,
  base_amount: 100,
  active: true,
  cooldown: 3,
  rarity: "legendary"
})

SeedHelper.create_item(%{
  code: "linkens_sphere",
  name: "Linken's Sphere",
  base_hp: 100,
  cooldown: 5,
  rarity: "legendary",
  passive: true
})

SeedHelper.create_item(%{
  code: "dagon5",
  name: "Dagon5",
  base_hp: 30,
  base_mp: 17,
  active: true,
  mp_cost: 5,
  cooldown: 3,
  rarity: "legendary",
  base_amount: 150
})

SeedHelper.create_item(%{
  code: "silver_edge",
  name: "Silver Edge",
  base_amount: 30,
  rarity: "legendary",
  base_hp: 11,
  base_mp: 6,
  base_atk: 2,
  base_speed: 20,
  passive: true,
  active: true
})

# SKILLS

SeedHelper.create_skill(%{
  code: "blade_fury",
  name: "Blade Fury",
  atk_multiplier: 1.4,
  armor_amount: 25,
  mp_cost: 10,
  cooldown: 2,
  damage_type: "normal"
})

SeedHelper.create_skill(%{
  code: "blink_strike",
  name: "Blink Strike",
  base_damage: 25,
  base_amount: 70,
  atk_multiplier: 0.8,
  other_atk_multiplier: 1.6,
  mp_cost: 11,
  cooldown: 3,
  power_amount: 4,
  damage_type: "normal"
})

SeedHelper.create_skill(%{
  code: "counter_helix",
  name: "Counter Helix",
  hp_multiplier: 0.07,
  passive: true,
  roll_number: 20
})

SeedHelper.create_skill(%{
  code: "death_pulse",
  name: "Death Pulse",
  atk_multiplier: 1.3,
  hp_regen_multiplier: 0.9,
  base_amount: 20,
  base_damage: 20,
  mp_cost: 12,
  cooldown: 2
})

SeedHelper.create_skill(%{
  code: "decay",
  name: "Decay",
  atk_multiplier: 0.5,
  hp_regen_multiplier: 0.06,
  mp_cost: 4,
  cooldown: 2,
  damage_type: "normal"
})

SeedHelper.create_skill(%{
  code: "double_edge",
  name: "Double Edge",
  atk_multiplier: 1.8,
  other_atk_multiplier: 0.5,
  mp_cost: 0,
  cooldown: 2,
  damage_type: "normal"
})

SeedHelper.create_skill(%{
  code: "echo_stomp",
  name: "Echo Stomp",
  atk_multiplier: 2.5,
  other_atk_multiplier: 1.5,
  base_amount: 5,
  base_damage: 10,
  mp_cost: 10,
  cooldown: 2,
  level_requirement: 2,
  damage_type: "normal"
})

SeedHelper.create_skill(%{
  code: "empower",
  name: "Empower",
  atk_multiplier: 1.0,
  power_amount: 40,
  mp_cost: 5,
  cooldown: 2,
  duration: 3,
  damage_type: "normal"
})

SeedHelper.create_skill(%{
  code: "feast",
  name: "Feast",
  passive: true,
  base_amount: 20,
  hp_regen_multiplier: 0.3,
  level_requirement: 8,
  damage_type: "none"
})

SeedHelper.create_skill(%{
  code: "fiery_soul",
  name: "Fiery Soul",
  passive: true,
  power_amount: 5,
  damage_type: "none"
})

SeedHelper.create_skill(%{
  code: "fury_swipes",
  name: "Fury Swipes",
  duration: 3,
  passive: true,
  base_damage: 14,
  level_requirement: 7,
  damage_type: "normal"
})

SeedHelper.create_skill(%{
  code: "illuminate",
  name: "Illuminate",
  base_damage: 300,
  base_amount: 150,
  mp_cost: 10,
  cooldown: 2,
  level_requirement: 10
})

SeedHelper.create_skill(%{
  code: "jinada",
  name: "Jinada",
  power_amount: 20,
  passive: true,
  level_requirement: 6,
  damage_type: "normal"
})

SeedHelper.create_skill(%{
  code: "lightning_bolt",
  name: "Lightning Bolt",
  atk_multiplier: 1.6,
  mp_multiplier: 0.15,
  mp_cost: 12,
  cooldown: 2
})

SeedHelper.create_skill(%{
  code: "maledict",
  name: "Maledict",
  base_damage: 20,
  atk_multiplier: 0.8,
  mp_cost: 11,
  cooldown: 3,
  power_amount: 10
})

SeedHelper.create_skill(%{
  code: "mana_shield",
  name: "Mana Shield",
  mp_multiplier: 0.25,
  atk_multiplier: 0,
  base_damage: 30,
  mp_cost: 15,
  cooldown: 3,
  level_requirement: 4
})

SeedHelper.create_skill(%{
  code: "mana_burn",
  name: "Mana Burn",
  atk_multiplier: 1.2,
  mp_multiplier: 0.15,
  other_mp_multiplier: 0.3,
  mp_cost: 12,
  cooldown: 2
})

SeedHelper.create_skill(%{
  code: "phase_shift",
  name: "Phase Shift",
  passive: true,
  roll_number: 10,
  mp_cost: 5,
  cooldown: 3,
  level_requirement: 5,
  damage_type: "none"
})

SeedHelper.create_skill(%{
  code: "shadow_word",
  name: "Shadow Word",
  mp_cost: 5,
  cooldown: 5,
  duration: 5,
  base_damage: 25,
  base_amount: 25,
  level_requirement: 9
})

SeedHelper.create_skill(%{
  code: "shuriken_toss",
  name: "Shuriken Toss",
  atk_multiplier: 1.8,
  armor_amount: 10,
  mp_cost: 6,
  cooldown: 2,
  damage_type: "normal"
})

SeedHelper.create_skill(%{
  code: "static_link",
  name: "Static Link",
  atk_multiplier: 1.0,
  mp_cost: 10,
  cooldown: 3,
  duration: 2,
  base_damage: 30,
  base_amount: 6,
  level_requirement: 3,
  damage_type: "normal"
})

# BOSS

SeedHelper.create_skill(%{
  code: "boss_slam",
  name: "Slam",
  cooldown: 3,
  base_damage: 300,
  enabled: false,
  mp_cost: 10
})

SeedHelper.create_skill(%{
  code: "boss_spell_block",
  name: "Spell Block",
  passive: true,
  cooldown: 3,
  enabled: false
})

SeedHelper.create_skill(%{
  code: "boss_bash",
  name: "Slam",
  passive: true,
  enabled: false
})

# ULTIMATES

assassinate =
  SeedHelper.create_skill(%{
    code: "assassinate",
    name: "Assassinate",
    atk_multiplier: 4.0,
    mp_cost: 10,
    cooldown: 5,
    ultimate: true,
    roll_number: 40,
    damage_type: "normal"
  })

bad_juju =
  SeedHelper.create_skill(%{
    code: "bad_juju",
    name: "Bad Juju",
    power_amount: 20,
    armor_amount: 20,
    mp_cost: 10,
    cooldown: 5,
    ultimate: true,
    duration: 5
  })

battle_trance =
  SeedHelper.create_skill(%{
    code: "battle_trance",
    name: "Battle Trance",
    mp_cost: 10,
    cooldown: 5,
    ultimate: true,
    passive: true,
    base_amount: 50,
    armor_amount: 12,
    power_amount: 12
  })

borrowed_time =
  SeedHelper.create_skill(%{
    code: "borrowed_time",
    name: "Borrowed Time",
    mp_cost: 8,
    cooldown: 5,
    ultimate: true,
    duration: 2,
    hp_regen_multiplier: 0.5
  })

coup =
  SeedHelper.create_skill(%{
    code: "coup",
    name: "Coup de Grace",
    power_amount: 35,
    roll_number: 20,
    passive: true,
    ultimate: true
  })

culling =
  SeedHelper.create_skill(%{
    code: "culling_blade",
    name: "Culling Blade",
    mp_cost: 7,
    atk_multiplier: 1.7,
    extra_multiplier: 0.3,
    cooldown: 5,
    ultimate: true,
    damage_type: "normal"
  })

doom =
  SeedHelper.create_skill(%{
    code: "doom",
    name: "Doom",
    hp_multiplier: 0.08,
    mp_multiplier: 0.08,
    mp_cost: 12,
    cooldown: 5,
    ultimate: true,
    duration: 2
  })

dream_coil =
  SeedHelper.create_skill(%{
    code: "dream_coil",
    name: "Dream Coil",
    mp_cost: 16,
    cooldown: 5,
    ultimate: true,
    base_damage: 100
  })

elder_dragon_form =
  SeedHelper.create_skill(%{
    code: "elder_dragon_form",
    name: "Elder Dragon Form",
    mp_cost: 10,
    cooldown: 5,
    ultimate: true,
    duration: 3,
    base_damage: 20,
    armor_amount: 15,
    power_amount: 15,
    damage_type: "normal"
  })

gods_strength =
  SeedHelper.create_skill(%{
    code: "gods_strength",
    name: "God's Strength",
    power_amount: 250,
    mp_cost: 9,
    cooldown: 5,
    ultimate: true,
    duration: 2,
    damage_type: "normal"
  })

guardian_angel =
  SeedHelper.create_skill(%{
    code: "guardian_angel",
    name: "Guardian Angel",
    base_amount: 100,
    mp_cost: 15,
    cooldown: 5,
    ultimate: true,
    atk_multiplier: 1.0,
    armor_amount: 30,
    duration: 2,
    damage_type: "normal"
  })

laguna =
  SeedHelper.create_skill(%{
    code: "laguna_blade",
    name: "Laguna Blade",
    atk_multiplier: 1.8,
    mp_cost: 15,
    cooldown: 5,
    ultimate: true,
    damage_type: "pure"
  })

life_drain =
  SeedHelper.create_skill(%{
    code: "life_drain",
    name: "Life Drain",
    atk_multiplier: 1.5,
    hp_regen_multiplier: 0.2,
    mp_cost: 18,
    cooldown: 5,
    extra_amount: 100,
    base_amount: 30,
    base_damage: 30,
    ultimate: true
  })

omnislash =
  SeedHelper.create_skill(%{
    code: "omnislash",
    name: "Omnislash",
    atk_multiplier: 1.5,
    other_atk_multiplier: 4.0,
    mp_cost: 10,
    cooldown: 5,
    ultimate: true,
    damage_type: "normal"
  })

psionic_trap =
  SeedHelper.create_skill(%{
    code: "psionic_trap",
    name: "Psionic Trap",
    mp_cost: 14,
    cooldown: 5,
    ultimate: true,
    duration: 2,
    base_damage: 40,
    armor_amount: 20,
    atk_multiplier: 0.2,
    roll_number: 90
  })

rearm =
  SeedHelper.create_skill(%{
    code: "rearm",
    name: "Rearm",
    power_amount: 30,
    atk_multiplier: 1.0,
    mp_cost: 10,
    cooldown: 5,
    ultimate: true
  })

remote_mines =
  SeedHelper.create_skill(%{
    code: "remote_mines",
    name: "Remote Mines",
    mp_cost: 25,
    cooldown: 5,
    ultimate: true,
    base_damage: 100,
    mp_multiplier: 0.5
  })

spell_steal =
  SeedHelper.create_skill(%{
    code: "spell_steal",
    name: "Spell Steal",
    power_amount: 40,
    atk_multiplier: 1.0,
    mp_cost: 8,
    cooldown: 5,
    ultimate: true
  })

time_lapse =
  SeedHelper.create_skill(%{
    code: "time_lapse",
    name: "Time Lapse",
    mp_cost: 8,
    cooldown: 5,
    extra_multiplier: 0.5,
    ultimate: true
  })

walrus_punch =
  SeedHelper.create_skill(%{
    code: "walrus_punch",
    name: "Walrus PUNCH!",
    mp_cost: 10,
    cooldown: 5,
    ultimate: true,
    base_damage: 140,
    atk_multiplier: 1.7,
    damage_type: "normal"
  })

boss_ult =
  SeedHelper.create_skill(%{
    code: "boss_ult",
    name: "Strength of the Immortal",
    mp_cost: 0,
    ultimate: true,
    passive: true,
    armor_amount: 10,
    power_amount: 10,
    enabled: false
  })

# AVATARS

tank = %{
  total_hp: 350,
  total_mp: 30,
  atk: 18,
  power: 0,
  armor: 20,
  speed: 0,
  hp_per_level: 20,
  mp_per_level: 3,
  atk_per_level: 2,
  role: "tank",
  enabled: true,
  description: "High defense, low mobility"
}

support = %{
  total_hp: 300,
  total_mp: 90,
  atk: 16,
  power: 10,
  armor: 10,
  speed: 0,
  hp_per_level: 12,
  mp_per_level: 7,
  atk_per_level: 1,
  role: "support",
  enabled: true,
  description: "Strategic caster"
}

bruiser = %{
  total_hp: 375,
  total_mp: 30,
  atk: 15,
  power: 10,
  armor: 10,
  speed: 0,
  hp_per_level: 16,
  mp_per_level: 3,
  atk_per_level: 3,
  role: "bruiser",
  enabled: true,
  description: "Good offense and defense"
}

nuker = %{
  total_hp: 255,
  total_mp: 100,
  atk: 17,
  power: 20,
  armor: 0,
  speed: 0,
  hp_per_level: 10,
  mp_per_level: 5,
  atk_per_level: 1,
  role: "nuker",
  enabled: true,
  description: "Powerful spellcaster"
}

carry = %{
  total_hp: 300,
  total_mp: 60,
  atk: 22,
  power: 10,
  armor: 0,
  speed: 10,
  hp_per_level: 10,
  mp_per_level: 2,
  atk_per_level: 4,
  role: "carry",
  enabled: true,
  description: "High offense and high mobility"
}

SeedHelper.create_avatar(
  Map.merge(
    %{
      name: "Abaddon",
      code: "abaddon",
      ultimate: borrowed_time,
      ultimate_code: "borrowed_time",
      level_requirement: 5
    },
    tank
  )
)

SeedHelper.create_avatar(
  Map.merge(
    %{
      name: "Axe",
      code: "axe",
      ultimate: culling,
      ultimate_code: "culling_blade"
    },
    bruiser
  )
)

SeedHelper.create_avatar(
  Map.merge(
    %{
      name: "Dazzle",
      code: "dazzle",
      ultimate: bad_juju,
      ultimate_code: "bad_juju"
    },
    support
  )
)

SeedHelper.create_avatar(
  Map.merge(
    %{
      name: "Doom",
      code: "ddoom",
      ultimate: doom,
      ultimate_code: "doom",
      level_requirement: 2
    },
    tank
  )
)

SeedHelper.create_avatar(
  Map.merge(
    %{
      name: "Dragon Knight",
      code: "dragon_knight",
      ultimate: elder_dragon_form,
      ultimate_code: "elder_dragon_form"
    },
    tank
  )
)

SeedHelper.create_avatar(
  Map.merge(
    %{
      name: "Juggernaut",
      code: "juggernaut",
      ultimate: omnislash,
      ultimate_code: "omnislash"
    },
    carry
  )
)

SeedHelper.create_avatar(
  Map.merge(
    %{
      name: "Lina",
      code: "lina",
      ultimate: laguna,
      ultimate_code: "laguna_blade",
      damage_type: "pure"
    },
    nuker
  )
)

SeedHelper.create_avatar(
  Map.merge(
    %{
      name: "Omniknight",
      code: "omniknight",
      ultimate: guardian_angel,
      ultimate_code: "guardian_angel",
      level_requirement: 10
    },
    support
  )
)

SeedHelper.create_avatar(
  Map.merge(
    %{
      name: "Phantom Assassin",
      code: "phantom_assassin",
      ultimate: coup,
      ultimate_code: "coup"
    },
    carry
  )
)

SeedHelper.create_avatar(
  Map.merge(
    %{
      name: "Puck",
      code: "puck",
      ultimate: dream_coil,
      ultimate_code: "dream_coil"
    },
    nuker
  )
)

SeedHelper.create_avatar(
  Map.merge(
    %{
      name: "Pugna",
      code: "pugna",
      ultimate: life_drain,
      ultimate_code: "life_drain",
      level_requirement: 7
    },
    nuker
  )
)

SeedHelper.create_avatar(
  Map.merge(
    %{
      name: "Rubick",
      code: "rubick",
      ultimate: spell_steal,
      ultimate_code: "spell_steal",
      level_requirement: 15
    },
    nuker
  )
)

SeedHelper.create_avatar(
  Map.merge(
    %{
      name: "Sniper",
      code: "sniper",
      ultimate: assassinate,
      ultimate_code: "assassinate"
    },
    carry
  )
)

SeedHelper.create_avatar(
  Map.merge(
    %{
      name: "Sven",
      code: "sven",
      ultimate: gods_strength,
      ultimate_code: "gods_strength",
      level_requirement: 6
    },
    bruiser
  )
)

SeedHelper.create_avatar(
  Map.merge(
    %{
      name: "Techies",
      code: "techies",
      ultimate: remote_mines,
      ultimate_code: "remote_mines"
    },
    nuker
  )
)

SeedHelper.create_avatar(
  Map.merge(
    %{
      name: "Templar Assassin",
      code: "templar_assassin",
      ultimate: psionic_trap,
      ultimate_code: "psionic_trap",
      level_requirement: 2
    },
    carry
  )
)

SeedHelper.create_avatar(
  Map.merge(
    %{
      name: "Tinker",
      code: "tinker",
      ultimate: rearm,
      ultimate_code: "rearm",
      level_requirement: 13
    },
    nuker
  )
)

SeedHelper.create_avatar(
  Map.merge(
    %{
      name: "Troll Warlord",
      code: "troll_warlord",
      ultimate: battle_trance,
      ultimate_code: "battle_trance",
      level_requirement: 8
    },
    carry
  )
)

SeedHelper.create_avatar(
  Map.merge(
    %{
      name: "Tusk",
      code: "tusk",
      ultimate: walrus_punch,
      ultimate_code: "walrus_punch"
    },
    bruiser
  )
)

SeedHelper.create_avatar(
  Map.merge(
    %{
      name: "Weaver",
      code: "weaver",
      ultimate: time_lapse,
      ultimate_code: "time_lapse",
      level_requirement: 4
    },
    carry
  )
)

SeedHelper.create_avatar(
  Map.merge(
    %{
      name: "Roshan",
      code: "boss",
      ultimate: boss_ult,
      ultimate_code: "boss_ult",
      total_hp: 3000,
      atk: 100,
      enabled: false
    },
    %{}
  )
)

SeedHelper.create_pvp_bots()

# generates all further skill levels with same values as level 1
Game.Query.SkillQuery.base_canon()
|> Repo.all()
|> Enum.map(fn skill ->
  range =
    if skill.ultimate do
      2..3
    else
      2..5
    end

  Enum.each(range, fn level ->
    skill
    |> Repo.preload(:match)
    |> Map.put(:id, nil)
    |> Map.put(:level, level)
    |> Repo.insert!()
  end)
end)

Repo.update_all(Item, set: [current: true])
Repo.update_all(Skill, set: [current: true])
Repo.update_all(Avatar, set: [current: true])

Repo.insert(%Quest{code: "season", level: 1, shard_prize: 100, initial_value: 0, final_value: 2})
Repo.insert(%Quest{code: "season", level: 2, shard_prize: 150, initial_value: 0, final_value: 5})
Repo.insert(%Quest{code: "season", level: 3, shard_prize: 200, initial_value: 0, final_value: 10})
Repo.insert(%Quest{code: "season", level: 4, shard_prize: 250, initial_value: 0, final_value: 15})
Repo.insert(%Quest{code: "season_master", level: 5, shard_prize: 250, initial_value: 0, final_value: 15})
Repo.insert(%Quest{code: "season_grandmaster", level: 6, shard_prize: 250, initial_value: 0, final_value: 15})
Repo.insert(%Quest{code: "season_perfect", level: 7, shard_prize: 250, initial_value: 0, final_value: 15})

Repo.insert(%Quest{code: "daily_master", level: 1, shard_prize: 100, initial_value: 0, final_value: 1, daily: true})

Repo.insert(%Quest{code: "daily_grandmaster", level: 1, shard_prize: 100, initial_value: 0, final_value: 1, daily: true})

Repo.insert(%Quest{code: "daily_perfect", level: 1, shard_prize: 100, initial_value: 0, final_value: 1, daily: true})

Moba.start!()

(Enum.to_list(0..10) ++ Enum.to_list(17..22))
|> Moba.regenerate_pve_bots!()
