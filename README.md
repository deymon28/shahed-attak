# Shahed Attack: Air War 0.6.7

A Factorio 2.0.77+ mod: reconnaissance, strike and heavy drones, hostile airfields, ballistic launch sites, AA guns, early-warning radar and anti-ballistic missile (ABM) batteries. Space Age is not required.

## Battery target selection

Open an ABM battery and use the **ABM targets** drop-down beside its ammunition inventory: **Ballistic missiles only** (default), **Ballistic missiles and Shaheds**, or **Shaheds only**. Each battery stores its own mode.

## Defending

Ordinary stationary turrets do not target drones. Players can shoot drones with hand-held and vehicle weapons. The dedicated AA turret only engages air targets: 36-tile range, one shot every 24 ticks, 62% default accuracy.

| Defense | Range | Behavior |
| --- | ---: | --- |
| AA turret | 36 | 18 physical + 12 explosive damage before resistances |
| ABM battery | 192 | Fast guided interceptors |
| Radar (drones) | 384 | Warning when arrival is within 60 seconds |
| Radar (ballistic) | 2048 | Early warning and impact-area marker |

## Warnings

A powered radar usually gives 30-60 seconds to react. Connect the radar to a programmable speaker with a red or green wire and use `shahed-attack-air-raid-signal` or `shahed-attack-ballistic-signal` with a `> 0` condition.

## Commands

```text
/shahed-attack status
/shahed-attack recon
/shahed-attack raid
/shahed-attack heavy-raid
/shahed-attack ballistic
```

## Development

Set `FACTORIO_EXE` (and optionally `FACTORIO_DATA`) before running the Factorio-based tests, and `BLENDER_EXE` for the render pipeline.

```powershell
.\tests\run-all.ps1
.\tools\build.ps1
```
