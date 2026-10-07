# Design

README.md is the player guide. This document maps the runtime code and records the invariants that changes must preserve.

## Module map

| Module | Responsibility |
| --- | --- |
| `control.lua` | Event wiring and update cadence (every tick, every 60 ticks, every 600 ticks); handlers are wrapped by `scripts/profiler.lua`. |
| `scripts/state.lua` | The whole storage schema (version 6), Nauvis-only scope, schema migration and surface cleanup. Other modules never create root tables themselves. |
| `scripts/lib/config.lua` | All setting reads, with defaults in one table. |
| `scripts/balance.lua` | Pure threat-progression math: raid size and interval, composition shares, ballistic salvo size and interval, eligibility, crash outcomes. |
| `scripts/lib/air_rules.lua` | Engagement constants, ballistic classes, flight profile, warhead rings, hit probability and magazine reload. |
| `scripts/director.lua` | Natural attack scheduling, ballistic availability, salvos, combined strikes and the pending-launch queue. |
| `scripts/raids.lua` | Drone raids: group planning, flight commands, decoys, suppression targets, moving targets, warheads, wrecks. |
| `scripts/ballistics.lua` | Missile launch, flight, warnings, impact markers and impact damage. |
| `scripts/defense.lua` | Defense registry, ABM fire control (fixed batteries and wagons), AA wagon fire control, launcher status. |
| `scripts/ordnance.lua` | Visible flak rounds and interceptors, encounter rolls, engagement counting, self-destruct. |
| `scripts/targeting.lua` | Compact registry of attackable player entities, target sampling, defense lookup. |
| `scripts/infrastructure.lua` | Enemy airfields and launch sites: deterministic placement near nests, registry, range queries. |
| `scripts/alerts.lua`, `radar_signals.lua`, `audio.lua` | Warnings, circuit signals and positional sound. |
| `scripts/battery_gui.lua`, `stats_gui.lua`, `range_overlay.lua` | Launcher side panels, statistics window, map range circles. |
| `scripts/commands.lua` | `/shahed-attack` command and the `shahed_attack` remote interface. |

## Invariants

- **Attacks start at real bases.** `raids.spawn_event` and `ballistics.launch` require a valid airfield or launch site; there is no external origin. Scripted events select a registered source near a position.
- **Nauvis only.** `state.ensure_surface` returns nil for other surfaces; registries ignore entities elsewhere.
- **Settings through `config`.** Never read `settings.global[name].value` with `and/or` fallbacks: a disabled boolean must stay `false`.
- **Compact registries.** Target lists are arrays with swap-remove; sources and defenses are maps keyed by unit number. Destroyed entities are removed through `on_object_destroyed` registrations that carry the unit number.
- **Determinism.** All randomness uses the per-surface generators in storage (`rng_state` for planning, `combat_rng_state` for hits). Iteration that affects outcomes is ordered (sorted projectile and pending-event ids).
- **Fire doctrine.** `surface_state.engagements[key]` counts interceptors in flight per target (`m<missile id>` or `d<drone unit>`). A shot releases its count when it hits, misses, self-destructs or is removed. `ordnance.recount` rebuilds the table after a configuration change.
- **Magazines.** `launcher_rounds[unit] = {rounds, reload_tick}`; one canister returns every `ABM_RELOAD_TICKS`. Interceptor items are consumed only on launch.
- **Derived caches are not authoritative.** `defense.lua` caches positions of fixed batteries and radars in a module-local table; each missile stores the launchers that can reach it (`missile.launchers`, refreshed every 30 ticks with its radar coverage). Both are rebuilt identically on every peer, so they never cause desyncs; anything that moves batteries or radars by script must not rely on them.
- **Ballistic classes** are fixed per missile at launch (`missile.class`); missiles from older saves are treated as heavy.
- **Ground turrets ignore aircraft.** `prototypes/ground_defense.lua` applies to every ammo, electric and fluid turret not created by this mod, and gives turret-fired ammunition ground-only damage types to which drones are immune.

## Threat progression

Raid size: `2 + 22 * evolution^1.4`, times the size multiplier and the reconnaissance bonus, plus the adaptive bonus (1.5 per AA mount within 64 tiles, 2 per drone-engaging ABM launcher), capped by the maximum raid size and the active-drone limit. Raids are split into groups of eight with 15-45 s between groups.

Ballistic progress `p` runs from 0 at the start evolution to 1 at full evolution. Class: light below 0.35, medium below 0.7, heavy above. Salvo: `1 + p * (max - 1) * U(0.5, 1)`. Interval: `lerp(3, 0.8, p)` days times `U(0.8, 1.2)`, divided by the frequency multiplier.

## Storage migration

`state.migrate` runs on configuration change before module initialization. From schema 5 it converts holey lists to keyed maps, rebuilds registrations, converts the ballistic schedule from days to ticks, converts readiness from a deadline to the chemistry tick, and removes surfaces other than Nauvis. `targeting.initialize` compacts legacy target lists and `infrastructure.initialize` keeps only the nest decisions that matter from the old inspected-spawner table.

## Development metadata

`info.json.in` holds the mod metadata. The source directory is not an installable mod name, so build and test tools copy the template to `info.json` only in their own output directories.
