storage.shahed_attack = storage.shahed_attack or {}
local root = storage.shahed_attack

root.schema_version = math.max(root.schema_version or 1, 4)
root.surfaces = root.surfaces or {}
root.registration_owners = root.registration_owners or {}
root.source_registrations = root.source_registrations or {}
root.source_scan_queue = root.source_scan_queue or {}
root.defense_registrations = root.defense_registrations or {}
root.alert_sound_events = root.alert_sound_events or {}
root.alert_counters = root.alert_counters or {global_warning_dispatches = 0}
root.audio_cooldowns = root.audio_cooldowns or {}
root.audio_counters = root.audio_counters or {}
root.radar_relays = root.radar_relays or {}
root.radar_relay_registrations = root.radar_relay_registrations or {}
root.visual_records = root.visual_records or {}
root.visual_registrations = root.visual_registrations or {}
root.visual_counters = root.visual_counters or {ballistic_launches = 0, abm_launches = 0}
