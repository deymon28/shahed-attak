local alerts = require("scripts.alerts")
local audio = require("scripts.audio")
local ballistics = require("scripts.ballistics")
local battery_gui = require("scripts.battery_gui")
local commands_api = require("scripts.commands")
local defense = require("scripts.defense")
local director = require("scripts.director")
local forces = require("scripts.forces")
local infrastructure = require("scripts.infrastructure")
local ordnance = require("scripts.ordnance")
local profiler = require("scripts.profiler")
local radar_signals = require("scripts.radar_signals")
local raids = require("scripts.raids")
local range_overlay = require("scripts.range_overlay")
local state = require("scripts.state")
local stats_gui = require("scripts.stats_gui")
local targeting = require("scripts.targeting")
local visual_effects = require("scripts.visual_effects")

local wrap = profiler.wrap

local function initialize_modules()
  forces.initialize()
  state.initialize()
  targeting.initialize()
  infrastructure.initialize()
  defense.initialize()
  radar_signals.initialize()
  visual_effects.initialize()
  audio.initialize()
  director.initialize()
  battery_gui.initialize()
  range_overlay.initialize()
end

script.on_init(initialize_modules)

script.on_configuration_changed(function()
  state.migrate()
  initialize_modules()
  for _, surface_state in pairs(state.root().surfaces) do
    ordnance.recount(surface_state)
  end
end)

script.on_event(defines.events.on_gui_opened, battery_gui.on_opened)
script.on_event(defines.events.on_gui_closed, battery_gui.on_closed)
script.on_event(defines.events.on_gui_selection_state_changed, battery_gui.on_selection_changed)
script.on_event(defines.events.on_gui_click, stats_gui.on_click)
script.on_event(defines.events.on_lua_shortcut, stats_gui.on_shortcut)

script.on_event(defines.events.on_chunk_generated, infrastructure.on_chunk_generated)
script.on_event(defines.events.on_biter_base_built, infrastructure.on_biter_base_built)
script.on_event(defines.events.on_force_created, function(event)
  forces.configure_relations(event.force)
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, range_overlay.on_setting_changed)
script.on_event({
  defines.events.on_player_created,
  defines.events.on_player_joined_game,
  defines.events.on_player_changed_force,
  defines.events.on_player_removed
}, range_overlay.refresh)

script.on_event({
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.script_raised_built,
  defines.events.script_raised_revive
}, function(event)
  local entity = event.entity
  targeting.on_entity_created(entity)
  defense.on_entity_created(entity)
  radar_signals.on_entity_created(entity)
  infrastructure.on_entity_created(entity)
  visual_effects.on_entity_created(entity)
  range_overlay.add(entity)
end)

script.on_event(defines.events.on_object_destroyed, function(event)
  targeting.on_object_destroyed(event)
  defense.on_object_destroyed(event)
  radar_signals.on_object_destroyed(event)
  infrastructure.on_object_destroyed(event)
  visual_effects.on_object_destroyed(event)
  range_overlay.on_object_destroyed(event)
end)

script.on_event(defines.events.on_entity_died, raids.on_entity_died, {{filter = "type", type = "unit"}})
script.on_event(defines.events.on_script_trigger_effect, function(event)
  raids.on_script_trigger_effect(event)
  defense.on_script_trigger_effect(event)
end)

script.on_event(defines.events.on_surface_created, function(event)
  local surface = game.get_surface(event.surface_index)
  if state.supported(surface) then
    initialize_modules()
  end
end)
script.on_event(defines.events.on_surface_deleted, function(event)
  state.forget_surface(event.surface_index)
end)

script.on_event(defines.events.on_tick, wrap("on_tick", function(event)
  local tick = event.tick
  ballistics.update(tick)
  defense.update_drone_intercepts(tick)
  ordnance.update(tick)
  alerts.flush_sounds(tick)
  visual_effects.update(tick)
end))

script.on_nth_tick(60, wrap("nth_60", function(event)
  local tick = event.tick
  battery_gui.update()
  raids.update(tick)
  director.process_pending(tick)
  defense.update(tick)
  radar_signals.update(tick)
  infrastructure.update()
  targeting.update()
  stats_gui.update()
end))

script.on_nth_tick(600, wrap("nth_600", function(event)
  local tick = event.tick
  state.prune(tick)
  director.update(tick)
  alerts.update(tick)
  audio.update(tick)
end))

commands_api.register()
