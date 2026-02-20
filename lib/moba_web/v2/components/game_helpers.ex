defmodule MobaWeb.V2.Components.GameHelpers do
  @moduledoc """
  Game display helpers for v2 templates.

  Ported from `MobaWeb.GameHelpers` with HEEx-safe outputs:
  - No `content_tag`, no `raw/1`
  - Returns strings or structured data that components render
  """

  @league_names %{
    0 => "Bronze",
    1 => "Silver",
    2 => "Gold",
    3 => "Platinum",
    4 => "Diamond",
    5 => "Master",
    6 => "Grandmaster"
  }

  @pve_tier_names %{
    0 => "Initiate",
    1 => "Novice",
    2 => "Adept",
    3 => "Veteran",
    4 => "Expert",
    5 => "Master",
    6 => "Grandmaster",
    7 => "Invoker"
  }

  @role_names %{
    "tank" => "Tank",
    "bruiser" => "Bruiser",
    "carry" => "Carry",
    "nuker" => "Nuker",
    "support" => "Support"
  }

  # -------------------------------------------------------------------
  # Image URLs — reuse Waffle uploaders
  # -------------------------------------------------------------------

  def image_url(%{"code" => "basic_attack"}), do: "/images/basic_attack.png"
  def image_url(%{code: "basic_attack"}), do: "/images/basic_attack.png"
  def image_url(%{code: "disarmed"}), do: "/images/disarmed.png"
  def image_url(%{code: "invulnerable"}), do: "/images/invulnerable.png"
  def image_url(%{code: "evade"}), do: "/images/evade.png"
  def image_url(%{image: image} = resource), do: get_url(image, resource)
  def image_url(%{"image" => image} = resource), do: get_url(image, resource)
  def image_url(_), do: "/images/default_skill.png"

  def background_url(%{skin: %{background: background} = skin}), do: get_background_url(background, skin)
  def background_url(%{avatar: %{background: background} = avatar}), do: get_background_url(background, avatar)
  def background_url(%{background: background} = resource), do: get_background_url(background, resource)
  def background_url(%{"background" => background} = resource), do: get_background_url(background, resource)
  def background_url(_), do: "/images/default_background.jpg"

  # -------------------------------------------------------------------
  # Skill description — returns a map for tooltip rendering
  # -------------------------------------------------------------------

  @doc """
  Returns structured skill info for tooltip rendering.
  No HTML strings — components render the data.
  """
  def skill_info(%{code: "basic_attack"} = skill) do
    %{
      name: skill.name,
      level: nil,
      description: skill.description,
      mp_cost: nil,
      cooldown: nil,
      passive: false,
      damage_type: "normal",
      effects: nil
    }
  end

  def skill_info(skill) do
    %{
      name: skill.name,
      level: skill.level,
      description: skill.description,
      mp_cost: positive_or_nil(skill.mp_cost),
      cooldown: positive_or_nil(skill.cooldown),
      passive: skill.passive || false,
      damage_type: skill.damage_type,
      effects: resource_effects_text(skill)
    }
  end

  # -------------------------------------------------------------------
  # Skill description — returns an HTML string for Bootstrap tooltip titles
  # -------------------------------------------------------------------

  def skill_description(%{code: "basic_attack"} = skill) do
    "<h3 class='text-center'>#{skill.name}</h3>#{skill.description}"
  end

  def skill_description(skill, full_description \\ true, show_name \\ true) do
    name = show_name && "<h3 class='mb-1 text-center'>#{skill.name}</h3>"
    level = full_description && skill.level && "<h5 class='text-center'>Level #{skill.level}</h5>"
    full = (full_description && full_skill_description_html(skill)) || ""
    "#{name || ""}#{level || ""}<span class='text-dark'>#{skill.description}</span><div class='text-center'>#{full}</div>"
  end

  # -------------------------------------------------------------------
  # Item description — returns a map for tooltip rendering
  # -------------------------------------------------------------------

  @doc """
  Returns structured item info for tooltip rendering.
  """
  def item_info(item) do
    stats =
      [
        {:hp, item.base_hp},
        {:mp, item.base_mp},
        {:atk, item.base_atk},
        {:power, item.base_power},
        {:armor, item.base_armor},
        {:speed, item.base_speed}
      ]
      |> Enum.filter(fn {_key, val} -> val && val > 0 end)

    %{
      name: item.name,
      rarity: item.rarity,
      description: item.description,
      stats: stats,
      mp_cost: positive_or_nil(item.mp_cost),
      cooldown: positive_or_nil(item.cooldown),
      active: item.active,
      effects: resource_effects_text(item)
    }
  end

  # -------------------------------------------------------------------
  # Formatting helpers
  # -------------------------------------------------------------------

  def farming_amount_label(value) when is_integer(value) and value >= 1000, do: "#{div(value, 1000)}K"
  def farming_amount_label(value), do: "#{value}"

  def farming_per_turn_label(pve_tier) do
    start..endd = Moba.farm_per_turn(pve_tier)
    "#{start} - #{endd}"
  end

  def finished_time(%{finished_at: nil}), do: nil
  def finished_time(hero), do: Timex.diff(hero.finished_at, hero.inserted_at, :minutes)

  def league_name(tier) when is_integer(tier), do: Map.get(@league_names, tier, "Unknown")
  def league_name(_), do: "Unknown"

  def pve_tier_name(tier) when is_integer(tier), do: Map.get(@pve_tier_names, tier, "Unknown")
  def pve_tier_name(_), do: "Unknown"

  def role_name(role) when is_binary(role), do: Map.get(@role_names, role, String.capitalize(role))
  def role_name(_), do: "Unknown"

  def total_farm(hero) do
    (hero.total_gold_farm || 0) + (hero.total_xp_farm || 0)
  end

  def rarity_color("normal"), do: "gray"
  def rarity_color("rare"), do: "blue"
  def rarity_color("epic"), do: "purple"
  def rarity_color("legendary"), do: "red"
  def rarity_color(_), do: "gray"

  def damage_type_label("normal"), do: "Normal"
  def damage_type_label("magic"), do: "Magic"
  def damage_type_label("pure"), do: "Pure"
  def damage_type_label(_), do: nil

  def damage_type_color("normal"), do: "green"
  def damage_type_color("magic"), do: "purple"
  def damage_type_color("pure"), do: "red"
  def damage_type_color(_), do: "gray"

  # -------------------------------------------------------------------
  # Resource effects — plain text with bracket tags for styling
  # -------------------------------------------------------------------

  @doc """
  Processes the effects string, replacing placeholders with actual values.
  Returns a plain string with bracket tags like [armor]...[/armor].
  Components can parse these tags for colored rendering.
  """
  def resource_effects_text(resource) do
    (resource.effects || "")
    |> String.replace("[base_damage]", "#{Map.get(resource, :base_damage, 0)}")
    |> String.replace("[hp_multiplier]", multiplier_text(resource, :hp_multiplier))
    |> String.replace("[other_hp_multiplier]", multiplier_text(resource, :other_hp_multiplier))
    |> String.replace("[hp_regen_multiplier]", multiplier_text(resource, :hp_regen_multiplier))
    |> String.replace("[atk_multiplier]", multiplier_text(resource, :atk_multiplier))
    |> String.replace("[other_atk_multiplier]", multiplier_text(resource, :other_atk_multiplier))
    |> String.replace("[mp_multiplier]", multiplier_text(resource, :mp_multiplier))
    |> String.replace("[other_mp_multiplier]", multiplier_text(resource, :other_mp_multiplier))
    |> String.replace("[mp_regen_multiplier]", multiplier_text(resource, :mp_regen_multiplier))
    |> String.replace("[extra_multiplier]", multiplier_text(resource, :extra_multiplier))
    |> String.replace("[base_amount]", "#{Map.get(resource, :base_amount, 0)}")
    |> String.replace("[armor_amount]", "#{Map.get(resource, :armor_amount, 0)}")
    |> String.replace("[power_amount]", "#{Map.get(resource, :power_amount, 0)}")
    |> String.replace("[extra_amount]", "#{Map.get(resource, :extra_amount, 0)}")
    |> String.replace("[roll_number]", "#{Map.get(resource, :roll_number, 0)}")
    |> String.replace("[mp_cost]", "#{Map.get(resource, :mp_cost, 0)}")
  end

  @doc """
  Strips bracket tags from effects text, returning plain text.
  """
  def plain_effects_text(text) when is_binary(text) do
    text
    |> String.replace(~r/\[(?:armor|damage|power|hp|mp|status|speed)\]/, "")
    |> String.replace(~r/\[\/(?:armor|damage|power|hp|mp|status|speed)\]/, "")
    |> String.replace(~r/\n/, " ")
    |> String.trim()
  end

  def plain_effects_text(_), do: ""

  # -------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------

  def item_description(item) do
    effects = resource_effects_text(item)

    rarity =
      case item.rarity do
        "normal" -> "<span class='badge badge-light-dark'>Normal</span>"
        "rare" -> "<span class='badge badge-light-primary'>Rare</span>"
        "epic" -> "<span class='badge badge-light-purple'>Epic</span>"
        "legendary" -> "<span class='badge badge-light-danger'>Legendary</span>"
        _ -> ""
      end

    mp_cost =
      item.mp_cost && item.mp_cost > 0 &&
        "<span class='badge badge-light-primary'><i class='fa fa-bolt mr-1'></i> #{item.mp_cost}</span>"

    cooldown =
      item.cooldown && item.cooldown > 0 &&
        "<span class='badge badge-light-warning'><i class='fa fa-clock mr-1'></i> #{item.cooldown}</span>"

    base_hp = item.base_hp && item.base_hp > 0 && "<span class='badge badge-light-danger'><i class='fa fa-heart mr-1'></i> +#{item.base_hp} Health</span>"
    base_mp = item.base_mp && item.base_mp > 0 && "<span class='badge badge-light-info'><i class='fa fa-bolt mr-1'></i> +#{item.base_mp} Energy</span>"
    base_atk = item.base_atk && item.base_atk > 0 && "<span class='badge badge-light-success'><i class='fa fa-dagger mr-1'></i> +#{item.base_atk} Attack</span>"
    base_power = item.base_power && item.base_power > 0 && "<span class='badge badge-light-pink'><i class='fa fa-galaxy mr-1'></i> +#{item.base_power} Power</span>"
    base_armor = item.base_armor && item.base_armor > 0 && "<span class='badge badge-light-warning'><i class='fa fa-shield-halved mr-1'></i> +#{item.base_armor} Armor</span>"
    base_speed = item.base_speed && item.base_speed > 0 && "<span class='badge badge-light-purple'><i class='fa fa-running mr-1'></i> +#{item.base_speed} Speed</span>"

    "<h3 class='mb-1 text-center'>#{item.name}</h3><div class='text-center mb-1 mt-1'>#{rarity}</div><span class='text-dark'>#{item.description}</span><div class='text-center mb-2 mt-1'>#{base_hp || ""}#{base_mp || ""}#{base_atk || ""}#{base_power || ""}#{base_armor || ""}#{base_speed || ""}</div><div class='text-center mb-2 mt-1'>#{mp_cost || ""}#{cooldown || ""}</div><div class='text-center'>#{effects}</div>"
  end

  defp full_skill_description_html(skill) do
    effects = resource_effects_text(skill)
    damage_type = damage_type_html(skill)

    mp_cost =
      skill.mp_cost && skill.mp_cost > 0 &&
        "<span class='badge badge-light-primary'><i class='fa fa-bolt mr-1'></i>#{skill.mp_cost}</span>"

    cooldown =
      skill.cooldown && skill.cooldown > 0 &&
        "<span class='badge badge-light-warning'><i class='fa fa-clock mr-1'></i>#{skill.cooldown}</span>"

    passive =
      if skill.passive,
        do: "<span class='badge badge-light-dark'><i class='fa fa-dot-circle mr-1'></i>Passive</span>",
        else: ""

    "<div class='text-center mb-2 mt-1'>#{mp_cost || ""}#{cooldown || ""}#{passive}#{if damage_type, do: "#{damage_type}<br/>", else: ""}</div>#{effects}"
  end

  defp damage_type_html(%{damage_type: damage_type}) do
    case damage_type do
      "normal" -> "<span class='badge badge-light-success'><i class='fa fa-bahai mr-1'></i>Normal Damage</span>"
      "pure" -> "<span class='badge badge-light-danger'><i class='fa fa-bahai mr-1'></i>Pure Damage</span>"
      "magic" -> "<span class='badge badge-light-purple'><i class='fa fa-bahai mr-1'></i>Magic Damage</span>"
      _ -> nil
    end
  end

  defp positive_or_nil(nil), do: nil
  defp positive_or_nil(val) when val > 0, do: val
  defp positive_or_nil(_), do: nil

  defp multiplier_text(resource, key) do
    case Map.get(resource, key) do
      nil -> ""
      val -> "#{round(val * 100)}"
    end
  end

  # Image field needs to be converted to a map of atoms due to serialization
  defp get_url(image, resource) do
    image =
      if image && Map.get(image, "file_name") do
        for {key, val} <- image, into: %{}, do: {String.to_atom(key), val}
      else
        image
      end

    Moba.Image.url({image, resource}, :original)
  end

  defp get_background_url(background, resource) do
    background =
      if background && Map.get(background, "file_name") do
        for {key, val} <- background, into: %{}, do: {String.to_atom(key), val}
      else
        background
      end

    Moba.Background.url({background, resource}, :original)
  end
end
