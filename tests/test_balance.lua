-- Threat progression, settings access and engagement rules.
local h = require("tests.lib.harness")
h.reset()

local balance = require("scripts.balance")
local config = require("scripts.lib.config")
local random = require("scripts.lib.random")
local rules = require("scripts.lib.air_rules")
local targeting = require("scripts.targeting")

-- Settings: disabled toggles must stay disabled (regression for the
-- `value and value.value or fallback` bug).
settings.global["shahed-attack-ballistic-enabled"] = {value = false}
settings.global["shahed-attack-recon-enabled"] = {value = false}
h.check(config.global("shahed-attack-ballistic-enabled") == false, "disabled ballistic toggle reads false")
h.check(config.global("shahed-attack-recon-enabled", true) == false, "disabled toggle wins over fallback")
h.check(config.global("shahed-attack-decoys-enabled") == true, "missing setting uses the shared default")
settings.global["shahed-attack-intercept-accuracy"] = {value = 0}
h.check(config.global("shahed-attack-intercept-accuracy") == 0, "zero is a valid numeric value")
local player = {index = 1, valid = true}
h.player_settings[1] = {["shahed-attack-alert-sound"] = {value = false}}
h.check(config.player(player, "shahed-attack-alert-sound") == false, "per-player mute reads false")
h.check(config.player(player, "shahed-attack-show-defense-ranges") == true, "per-player default")

-- Random generator
local a, b = random.new(123456), random.new(123456)
for _ = 1, 20 do h.check(a:next_u32() == b:next_u32(), "PRNG reproducibility") end
local r = random.new(7)
for _ = 1, 100 do
  local value = r:range_int(3, 7)
  h.check(value >= 3 and value <= 7, "PRNG integer range")
end

-- Raid growth: small early, mass raids late, capped by the setting.
h.check(balance.raid_size(0, 1, 1, 0, 40) == 2, "early raid minimum")
h.check(balance.raid_size(0.5, 1, 1, 0, 40) >= 9, "mid-game raids are larger than the old cap of 6")
h.check(balance.raid_size(1, 1, 1, 0, 40) == 24, "late raid baseline")
h.check(balance.raid_size(1, 4, 2, 0, 40) == 40, "raid cap")
h.check(balance.raid_size(1, 1, 1, 30, 100) == 54, "known defenses add aircraft")
h.check(balance.adaptive_bonus(4, 1) == 8, "adaptive bonus per AA gun and ABM launcher")
h.check(balance.group_count(8) == 1 and balance.group_count(9) == 2 and balance.group_count(40) == 5, "groups of eight")
local previous = 0
for step = 0, 10 do
  local size = balance.raid_size(step / 10, 1, 1, 0, 100)
  h.check(size >= previous, "raid size never shrinks as evolution grows")
  previous = size
end
h.check(balance.raid_interval_days(1, 0.5, 1) < balance.raid_interval_days(0, 0.5, 1), "raids become more frequent")
h.check(math.abs(balance.raid_interval_days(0, 0.5, 2) - balance.raid_interval_days(0, 0.5, 1) / 2) < 1e-9,
  "frequency multiplier divides the interval")

-- Event kinds respect the reconnaissance toggle.
for roll = 0, 1, 0.01 do
  local kind = balance.choose_event_kind(roll, 1, false, false)
  h.check(kind == "raid", "recon disabled never yields recon or mixed raids")
end
h.check(balance.choose_event_kind(0.1, 0.2, true, false) == "recon", "recon without intelligence")
h.check(balance.choose_event_kind(0.2, 0.2, true, true) == "raid", "recon is rarer with intelligence")
h.check(balance.choose_event_kind(0.95, 0.5, true, false) == "mixed", "mixed raid when recon enabled")

-- Composition
h.check(balance.decoy_share(0.2, true) == 0 and balance.decoy_share(1, false) == 0, "decoys gated")
h.close(balance.decoy_share(1, true), 0.4, 1e-9, "decoy share cap")
h.check(balance.suppression_share(0.4, true) == 0 and balance.suppression_share(1, true) > 0, "suppression gated")
h.check(balance.drone_kind("raid", 1, 1, 0.01, true) == "decoy", "low roll is a decoy late")
h.check(balance.drone_kind("raid", 1, 1, 0.01, false) ~= "decoy", "decoys disabled")
h.check(balance.drone_kind("mixed", 1, 1, 0.9, true) == "recon", "mixed raid leads with recon")
h.check(balance.drone_kind("raid", 1, 0, 0.5, true) == "strike", "early raids are strike drones")

-- Ballistic progression
h.check(balance.progress(0.25, 0.25) == 0 and balance.progress(1, 0.25) == 1, "progress endpoints")
h.check(balance.ballistic_salvo(0, 8, 1) == 1, "first salvos are single missiles")
h.check(balance.ballistic_salvo(1, 8, 1) == 8, "full salvo at full evolution")
h.check(balance.ballistic_salvo(1, 8, 0) >= 4, "late salvos are large")
h.check(balance.ballistic_interval_days(1, 0.5, 1) < balance.ballistic_interval_days(0, 0.5, 1), "ballistics grow frequent")
h.check(balance.ballistic_eligible(11, 1, true, 12, 0.25) == false, "day gate")
h.check(balance.ballistic_eligible(12, 0.2, true, 12, 0.25) == false, "evolution gate")
h.check(balance.ballistic_eligible(12, 0.25, true, 12, 0.25) == true, "gates open")
h.check(balance.ballistic_eligible(50, 1, false, 12, 0.25) == false, "disabled")
h.check(balance.combined_strike_chance(0.1) == 0 and balance.combined_strike_chance(1) > 0, "combined strikes late")

h.check(rules.ballistic_class(0) == "light" and rules.ballistic_class(0.5) == "medium"
  and rules.ballistic_class(0.9) == "heavy", "missile classes by progression")
local light, heavy = rules.warhead_rings("light"), rules.warhead_rings("heavy")
h.check(light[1].explosion < heavy[1].explosion and light[4].radius < heavy[4].radius, "light warheads are weaker")
h.check(heavy[1].explosion == 1800 and heavy[4].radius == 32, "heavy warhead keeps the original strength")
h.check(rules.ballistic_duration(0, "light") == 50 * 60, "light missiles give the longest minimum warning")
h.check(rules.ballistic_duration(0, "heavy") == 38 * 60, "heavy missiles are faster")
h.check(rules.ballistic_duration(2400) == 100 * 60, "default class keeps the old 24 tiles/s profile")
for _ = 1, 200 do
  local offset = rules.aim_error(10, r:next_float(), r:next_float())
  h.check(math.sqrt(offset.x ^ 2 + offset.y ^ 2) <= 10 + 1e-9, "aim error stays within CEP")
end
h.check(rules.intercept_probability(0.7, rules.class_stats("heavy").hit_factor) < 0.7, "heavy missiles are harder")
h.check(rules.intercept_probability(1, 1.15) == 1, "probability clamps at one")

-- Magazine reload
local rounds, reload = rules.reload_magazine(nil, nil, 0)
h.check(rounds == 4 and reload == nil, "new launchers start full")
rounds, reload = rules.reload_magazine(0, 600, 599)
h.check(rounds == 0 and reload == 600, "no canister before the reload time")
rounds, reload = rules.reload_magazine(0, 600, 1200)
h.check(rounds == 2 and reload == 1800, "one canister per reload period")
rounds, reload = rules.reload_magazine(3, 600, 600)
h.check(rounds == 4 and reload == nil, "magazine stops reloading when full")

-- Crash outcomes
h.check(balance.crash_outcome("recon", 0.89, 0) == "safe", "recon safe crash")
h.check(balance.crash_outcome("strike", 0.95, 0) == "warhead", "strike warhead crash")
h.check(balance.crash_outcome("heavy", 0.80, 1) == "warhead", "heavy scaled warhead crash")
h.check(balance.crash_outcome("decoy", 0.9, 1) == "safe", "decoys rarely explode")

-- Target weights
h.check(targeting.base_weight("rocket-silo", "rocket-silo") == 100, "silo weight")
h.check(targeting.base_weight("locomotive", "locomotive") == 45, "trains are targets")
h.check(targeting.base_weight("cargo-wagon", "cargo-wagon") == 20, "wagons are targets")
h.check(targeting.base_weight("transport-belt", "transport-belt") == 0, "belts are not targets")
h.close(targeting.score(25, 1.5, 1), 56.25, 1e-9, "active polluted target score")

h.pass("threat progression, settings, ballistic classes, magazines and target weights")
