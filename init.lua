-- Vars

local function setting_get(name, default)
	return minetest.settings:get(name) or default
end

local speed         = tonumber(setting_get("sprint_speed", "1.3"))
local jump          = tonumber(setting_get("sprint_jump", "1.1"))
local dir           = minetest.is_yes(setting_get("sprint_forward_only", "false"))
local particles     = tonumber(setting_get("sprint_particles", "2"))
local stamina       = minetest.is_yes(setting_get("sprint_stamina", "true"))
local stamina_drain = tonumber(setting_get("sprint_stamina_drain", "2"))
local replenish     = tonumber(setting_get("sprint_stamina_replenish", "2"))
local starve        = minetest.is_yes(setting_get("sprint_starve", "true"))
local starve_drain  = tonumber(setting_get("sprint_starve_drain", "0.5"))
local starve_limit  = tonumber(setting_get("sprint_starve_limit", "6"))
local breath        = minetest.is_yes(setting_get("sprint_breath", "true"))
local breath_drain  = tonumber(setting_get("sprint_breath_drain", "1"))
local autohide      = minetest.is_yes(setting_get("hudbards_autohide_stamina", "false"))

local sprint_timer_step = 0.5
local sprint_timer = 0
local sprinting = {}
local stamina_timer = {}
local breath_timer = {}

local mod_hudbars = minetest.get_modpath("hudbars") ~= nil
local mod_player_monoids = minetest.get_modpath("player_monoids") ~= nil
local mod_playerphysics = minetest.get_modpath("playerphysics") ~= nil

if starve then
  if minetest.get_modpath("hbhunger") then
    starve = "hbhunger"
  elseif minetest.get_modpath("hunger_ng") then
    starve = "hunger_ng"
  else
    starve = false
  end
end
if minetest.settings:get_bool("creative_mode") then
  starve = false
end
-- Functions

local function start_sprint(player)
  if not sprinting[player:get_player_name()] then
    if mod_player_monoids then
      player_monoids.speed:add_change(player, speed, "hbsprint:speed")
      player_monoids.jump:add_change(player, jump, "hbsprint:jump")
    elseif mod_playerphysics then
      playerphysics.add_physics_factor(player, "speed", "hbsprint:speed", speed)
      playerphysics.add_physics_factor(player, "jump", "hbsprint:jump", jump)
    else
      player:set_physics_override({speed = speed, jump = jump})
    end
  end
end

local function stop_sprint(player)
  if sprinting[player:get_player_name()] then
    if mod_player_monoids then
      player_monoids.speed:del_change(player, "hbsprint:speed")
      player_monoids.jump:del_change(player, "hbsprint:jump")
    elseif mod_playerphysics then
      playerphysics.remove_physics_factor(player, "speed", "hbsprint:speed")
      playerphysics.remove_physics_factor(player, "jump", "hbsprint:jump")
    else
      player:set_physics_override({speed = 1, jump = 1})
    end
  end
end

local function drain_stamina(player)
  local player_stamina = tonumber(player:get_meta():get("hbsprint:stamina"))
  if player_stamina > 0 then
    player:get_meta():set_float("hbsprint:stamina", player_stamina - stamina_drain)
  end
  if mod_hudbars then
    if autohide and player_stamina < 20 then hb.unhide_hudbar(player, "stamina") end
    hb.change_hudbar(player, "stamina", player_stamina)
  end
end

local function replenish_stamina(player)
  local player_stamina = tonumber(player:get_meta():get("hbsprint:stamina"))
  if player_stamina < 20 then
    player:get_meta():set_float("hbsprint:stamina", player_stamina + stamina_drain)
  end
  if mod_hudbars then
    hb.change_hudbar(player, "stamina", player_stamina)
    if autohide and player_stamina == 20 then hb.hide_hudbar(player, "stamina") end
  end
end

local function drain_hunger(player, hunger, name)
  if hunger > 0 then
    local newhunger = hunger - starve_drain
    if starve == "hbhunger" then
      hbhunger.hunger[name] = newhunger
      hbhunger.set_hunger_raw(player)
    elseif starve == "hunger_ng" then
      hunger_ng.alter_hunger(name, - starve_drain, "Sprinting")
    end
  end
end

local function drain_breath(player)
  local player_breath = player:get_breath()
  if player_breath < 11 then
    player_breath = player_breath - breath_drain
    if player_breath > 0 then
      player:set_breath(player_breath)
    end
  end
end

local function create_particles(player, name, pos, ground)
  if ground and ground.name ~= "air" and ground.name ~= "ignore" then
    local def = minetest.registered_nodes[ground.name]
    local tile = def.tiles[1] or def.inventory_image or ""
    if type(tile) == "string" then
      for i = 1, particles do
        minetest.add_particle({
          pos = {x = pos.x + math.random(-1,1) * math.random() / 2, y = pos.y + 0.1, z = pos.z + math.random(-1,1) * math.random() / 2},
          velocity = {x = 0, y = 5, z = 0},
          acceleration = {x = 0, y = -13, z = 0},
          expirationtime = math.random(),
          size = math.random() + 0.5,
          vertical = false,
          texture = tile,
        })
      end
    end
  end
end

-- Registrations

if mod_hudbars and stamina then
  hb.register_hudbar(
    "stamina",
    0xFFFFFF,
    "Stamina",
    {
      bar = "sprint_stamina_bar.png",
      icon = "sprint_stamina_icon.png",
      bgicon = "sprint_stamina_bgicon.png"
    },
    20,
    20,
    autohide)
end

minetest.register_on_joinplayer(function(player)
  if mod_hudbars and stamina then hb.init_hudbar(player, "stamina", 20, 20, autohide) end
  player:get_meta():set_float("hbsprint:stamina", 20)
end)

minetest.register_globalstep(function(dtime)
  sprint_timer = sprint_timer + dtime
  if sprint_timer >= sprint_timer_step then
    for _,player in ipairs(minetest.get_connected_players()) do
      local ctrl = player:get_player_control()
      local key_press = false
      stamina_timer[player:get_player_name()] = (stamina_timer[player:get_player_name()] or 0) + sprint_timer
      breath_timer[player:get_player_name()] = (breath_timer[player:get_player_name()] or 0) + sprint_timer
      if dir then
        key_press = ctrl.aux1 and ctrl.up and not ctrl.left and not ctrl.right
      else
        key_press = ctrl.aux1
      end

      if key_press then
        local name = player:get_player_name()
        local hunger = 30
        local pos = player:get_pos()
        local ground = minetest.get_node_or_nil({x=pos.x, y=pos.y-1, z=pos.z})
        local walkable = false
        local player_stamina = tonumber(player:get_meta():get("hbsprint:stamina"))
        if starve == "hbhunger" then
          hunger = tonumber(hbhunger.hunger[name])
        elseif starve == "hunger_ng" then
          hunger = hunger_ng.get_hunger_information(name).hunger.exact
        end
        if ground ~= nil then
          local ground_def = minetest.registered_nodes[ground.name]
          if ground_def and (minetest.registered_nodes[ground.name].walkable or minetest.registered_nodes[ground.name].liquidtype ~= "none") then
            walkable = true
          end
        end
        if player_stamina > 0 and hunger > starve_limit and walkable then
          start_sprint(player)
          sprinting[name] = true
          if stamina then drain_stamina(player) end
          if starve then drain_hunger(player, hunger, name) end
          if breath then
            if breath_timer[name] >= 2 then
              drain_breath(player)
              breath_timer[name] = 0
            end
          end
          if particles then create_particles(player, name, pos, ground) end
        else
          stop_sprint(player)
          sprinting[name] = false
        end
      else
        stop_sprint(player)
        sprinting[player:get_player_name()] = false
        if stamina_timer[player:get_player_name()] >= replenish then
          if stamina then replenish_stamina(player) end
          stamina_timer[player:get_player_name()] = 0
        end
      end
    end
    sprint_timer = 0
  end
end)
