# Shahed Attack: Air War 0.7.0

A Factorio 2.0.77+ mod that adds an aerial enemy faction to Nauvis: reconnaissance drones, Shahed-style strike drones, heavy drones and decoys flying from enemy airfields, and ballistic missiles launched from enemy launch sites. You defend with AA guns, early-warning radar, missile-defense (ABM) batteries and rail AA/ABM wagons. Space Age is not required; the air war takes place on Nauvis only.

## How the threat grows

The enemy develops with biter evolution, the same way for drones and missiles:

| Evolution | Drone raids | Ballistic missiles |
| --- | --- | --- |
| Start | Small groups of 2-4 strike drones after a 2-day grace period | None |
| ~0.25 (and day 12, 30 min after chemical science) | Larger groups | Single **light** missiles: weak warhead, up to 10 tiles off target |
| ~0.3-0.5 | Decoys appear, raids grow to 10+ aircraft | **Medium** missiles, salvos of 2-4 |
| ~0.5-0.7 | Some aircraft attack AA guns, radars and ABM launchers near the target | Salvos, some combined with drone raids so both arrive together |
| ~0.7-1.0 | Mass raids of 20-40 aircraft in several groups from different directions, sized against your known defenses | **Heavy** missiles: accurate, faster, harder to intercept, salvos up to 8 |

- Every attack starts at a real enemy base. Airfields appear near biter nests at least 384 tiles from the map center; ballistic launch sites at least 640 tiles away. Destroying all bases of a type stops attacks of that type; aircraft already in the air continue.
- Mass raids are split into groups of up to eight. Groups take off 15-45 seconds apart and swing out to approach from different bearings.
- Decoys look like strike drones on radar and draw fire, but carry no real warhead.
- After successful reconnaissance (or from evolution 0.7) raids add aircraft for every known AA gun and drone-engaging missile launcher near the target.
- Shahed warheads are deliberately modest (strike 140, heavy 320 damage at the center); the danger comes from numbers.
- Trains are targets. Drones follow a train and attack it directly when they get close; trains waiting at stations are the easiest targets.

## Defending

Ordinary turrets (vanilla and from other mods) do not target drones, and their splash damage does not hit them. Players can shoot drones with hand-held and vehicle weapons.

| Defense | Range | Behavior |
| --- | ---: | --- |
| Anti-air turret | 36 | Flak shells: 18 physical + 12 explosive damage, 62% hit chance by default |
| Missile-defense battery | 192 | 4 ready canisters, reloads one every 10 s from its ammunition; each launch uses one interceptor and 10 MJ |
| Anti-air wagon | 30 | Script-aimed flak mount on a rail car; loads flak magazines from its cargo slots |
| Missile-defense wagon | 128 | Missile launcher on a rail car, no power needed; 4 ready canisters, interceptors from its cargo slots |
| Early-warning radar | 384 / 2048 | Warns about drones / ballistic missiles about 60 seconds before arrival |

**Fire doctrine.** Missile-defense launchers coordinate: no more than two interceptors (configurable) fly toward one target at a time. When an interceptor misses, another launcher fires (shoot-look-shoot). A salvo larger than your ready canisters will get through, so spread launchers and keep them supplied.

**Hit probability.** The base interceptor accuracy is 70%. Light missiles are easier to hit (×1.15), heavy missiles harder (×0.8), drones easier (×1.15).

**Target modes.** Open an ABM battery or ABM wagon and use the **ABM targets** drop-down: ballistic missiles only (battery default), ballistic missiles and Shaheds (wagon default), or Shaheds only. The same panel shows readiness, interceptors in stock, ready canisters and the next reload. The AA wagon panel shows its flak rounds.

**Map ranges.** AA and missile-defense coverage is drawn on the map view. Each player can switch defense ranges and radar ranges on or off in the per-player mod settings.

## Warnings

A powered radar usually gives 30-60 seconds to react. Without radar coverage you only get a late warning: drones within 50 tiles of the target, ballistic missiles in their last 8 seconds. Directions name the side the threat comes **from**. Alerts use separate icons for air raids and ballistic missiles; the expected ballistic impact area blinks in the world and on the map.

Connect a radar with a red or green wire to an ordinary programmable speaker and use `shahed-attack-air-raid-signal` or `shahed-attack-ballistic-signal` with a `> 0` condition. Signals are held for 600 ticks after the last detection. The `both`, `global-sound` and `circuit-only` delivery modes control sound and circuit output; personal mute does not affect the circuit.

## Statistics

The **Air war statistics** shortcut (or `/shahed-attack stats`) opens a window with enemy evolution, the current ballistic threat, time to the next raid and ballistic attempt, aircraft and missiles in flight, known enemy bases, and totals for raids, drones, decoys, interceptions, impacts and flak.

## Settings

Map settings (per save): raid frequency, raid size, maximum raid size, grace period, drone damage, reconnaissance / decoys / attacks on air defenses / adaptive raids on or off, maximum drones in the air, ballistic strikes on or off, ballistic frequency, earliest ballistic day, start evolution, preparation time after chemical science, maximum salvo, ballistic damage, AA accuracy, interceptor accuracy, interceptors per target and alert delivery.

Per player: alert sounds, detailed alerts, defense ranges on the map, radar ranges on the map.

## Commands

```text
/shahed-attack help
/shahed-attack status
/shahed-attack stats
/shahed-attack sources
/shahed-attack recon
/shahed-attack raid [size]
/shahed-attack heavy-raid [size]
/shahed-attack mass-raid [size]
/shahed-attack ballistic [salvo]
/shahed-attack clear
```

Attack commands and `clear` need admin rights. Scripted attacks also start from real enemy bases; they fail with `no-source` when none is in range. The `shahed_attack` remote interface provides `schedule_event`, `get_surface_state`, `get_alert_delivery_state`, `set_alert_delivery`, `set_intercept_accuracy`, `set_setting`, `clear_threats`, `start_profiling` and `stop_profiling`.

## Saves

Saves from 0.4.0 onward upgrade automatically. Active threats, bases, counters and battery modes are kept. Missiles already in flight from an older version keep their full warhead.

## Development

Set `FACTORIO_EXE` (and optionally `FACTORIO_DATA`) before running the Factorio-based tests, and `BLENDER_EXE` for the render pipeline. Lua 5.4 (`lua`, `luac`) and Python 3 with pytest and Pillow are needed for the standalone tests.

```powershell
.\tests\run-all.ps1
python tools\check_lua_globals.py
.\tests\benchmark.ps1
.\tools\build.ps1
```

See [docs/DESIGN.md](docs/DESIGN.md) for the architecture and [docs/PERFORMANCE.md](docs/PERFORMANCE.md) for measurements. Development-only art sources (Blender scenes, renders, imported models) are not part of the repository or the release archive.
