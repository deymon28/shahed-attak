local ordnance = require("scripts.ordnance")
local state = require("scripts.state")
local forces = require("scripts.forces")
local targeting = require("scripts.targeting")
local infrastructure = require("scripts.infrastructure")
local raids = require("scripts.raids")
local ballistics = require("scripts.ballistics")
local defense = require("scripts.defense")
local battery_gui = require("scripts.battery_gui")
local director = require("scripts.director")
local commands_api = require("scripts.commands")
local alerts = require("scripts.alerts")
local audio = require("scripts.audio")
local radar_signals = require("scripts.radar_signals")
local visual_effects = require("scripts.visual_effects")

script.on_init(function()
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
end)

script.on_configuration_changed(function()
  forces.initialize()
  state.initialize()
  targeting.initialize()
  infrastructure.initialize()
  defense.initialize()
  radar_signals.initialize()
  visual_effects.initialize()
  audio.initialize()
  director.on_configuration_changed()
  battery_gui.initialize()
end)

script.on_event(defines.events.on_gui_opened, battery_gui.on_opened)
script.on_event(defines.events.on_gui_closed, battery_gui.on_closed)
script.on_event(defines.events.on_gui_selection_state_changed, battery_gui.on_selection_changed)

script.on_event(defines.events.on_chunk_generated, infrastructure.on_chunk_generated)
script.on_event(defines.events.on_biter_base_built, infrastructure.on_biter_base_built)
script.on_event(defines.events.on_force_created, function(event)
  forces.configure_relations(event.force)
end)

local build_events = {
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.script_raised_built,
  defines.events.script_raised_revive
}
script.on_event(build_events, function(event)
  local entity = event.entity
  targeting.on_entity_created(entity)
  defense.on_entity_created(entity)
  radar_signals.on_entity_created(entity)
  infrastructure.on_entity_created(entity)
  visual_effects.on_entity_created(entity)
end)

script.on_event(defines.events.on_object_destroyed, function(event)
  targeting.on_object_destroyed(event)
  defense.on_object_destroyed(event)
  radar_signals.on_object_destroyed(event)
  infrastructure.on_object_destroyed(event)
  visual_effects.on_object_destroyed(event)
end)

script.on_event(defines.events.on_entity_died, raids.on_entity_died)
script.on_event(defines.events.on_script_trigger_effect, function(event)
  raids.on_script_trigger_effect(event)
  defense.on_script_trigger_effect(event)
end)
script.on_event(defines.events.on_surface_created, function(event)
  local surface = game.get_surface(event.surface_index)
  if surface then
    state.ensure_surface(surface)
    targeting.queue_surface_scan(surface)
    infrastructure.initialize()
    defense.initialize()
    radar_signals.initialize()
    visual_effects.initialize()
  end
end)
script.on_event(defines.events.on_surface_deleted, function(event)
  if storage.shahed_attack and storage.shahed_attack.surfaces then
    storage.shahed_attack.surfaces[event.surface_index] = nil
    for unit, surface_index in pairs(storage.shahed_attack.source_inspected or {}) do
      if surface_index == event.surface_index then storage.shahed_attack.source_inspected[unit] = nil end
    end
    storage.shahed_attack.source_scan_queue[event.surface_index] = nil
  end
end)
script.on_event(defines.events.on_tick, function(event)
  ballistics.update(event.tick)
  defense.update_drone_intercepts(event.tick)
  ordnance.update(event.tick)
  alerts.flush_sounds(event.tick)
  visual_effects.update(event.tick)
end)
script.on_nth_tick(60, function(event)
  battery_gui.update()
  raids.update(event.tick)
  defense.update(event.tick)
  radar_signals.update(event.tick)
  infrastructure.update()
end)
script.on_nth_tick(600, function(event)
  state.prune(event.tick)
  targeting.update()
  director.update(event.tick)
  alerts.update(event.tick)
  audio.update(event.tick)
end)

commands_api.register()
