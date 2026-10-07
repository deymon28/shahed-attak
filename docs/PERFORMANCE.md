# Performance

## How to measure

`tests/benchmark.ps1` runs the `benchmark-air-war` scenario until a sustained battle is in progress, saves the game, and runs Factorio's `--benchmark` on that save (3 runs × 3600 ticks by default). The world: 400 assembling machines, 48 AA turrets, 24 ABM batteries and 16 radars; four airfields send 4 × 10 drones every 5 seconds and a launch site fires a missile every 2 seconds. It uses only remote calls that exist in 0.6.x and 0.7.x, so `-ModSource <older checkout>` measures an older version on the same world.

When the measured version supports it, the scenario also calls `start_profiling` / `stop_profiling`, which log the average time per game tick of each subsystem (`SHAHED_PROFILE` lines in `factorio-current.log`).

## Results (Factorio 2.0.77, 2026-10-07)

Whole-game update time from `--benchmark`, three runs each:

| Version | Average per tick |
| --- | --- |
| 0.6.7 | 5.79 / 6.21 / 5.82 ms |
| 0.7.0 before optimization | 4.10 / 3.67 / 4.76 ms |
| 0.7.0 | 1.29 / 1.45 / 1.41 ms |

The world is the same, but the fight is not identical: 0.7.0 launches fewer interceptors because of the fire doctrine, so part of the gap is gameplay rather than code. The per-subsystem profile isolates the mod's own cost:

| Subsystem (ms per tick) | Before optimization | After |
| --- | ---: | ---: |
| Ballistic missiles (every tick) | 0.792 | 0.142 |
| Radar circuit signals (every second, averaged) | 0.089 | 0.007 |
| Drone raids (every second, averaged) | 0.105 | 0.075 |
| Drone interception and AA wagons | 0.012 | 0.013 |
| Everything else | < 0.03 | < 0.03 |

Maximum single-tick spikes (150-270 ms in both versions) come from world generation along the drones' flight paths and entity creation in the benchmark world, not from the mod's periodic updates.

## What was changed

- Each missile refreshes, twice a second, the list of launchers that can reach it (range plus a 64-tile margin) together with its radar coverage. Before, every missile checked every launcher every tick.
- Fixed batteries and radars cache their position; rail launchers still read their live position.
- Missile renders write only the properties that change (visibility once, light scale once, marker radius on change).
- Radar signals read threat positions once per update for all radars, and the hidden combinator is written only when its values change. Relay wiring is no longer re-checked every second.
- Drone updates read the drone position once per update.
- Surfaces with no missiles, drones or projectiles skip those updates entirely.
