# Air War 0.5.0 implementation design

The approved requirements are in superpowers/specs/2026-09-05-air-war-overhaul.md. README.md is the player-facing guide; UPGRADE_PROGRESS.md and VERIFICATION.md track measured evidence.

## Threats and sources

The director selects production targets and launches only from registered, destructible infrastructure. Deterministic independent placement examines every eligible enemy spawner, persists placement decisions, and backfills 32 chunks per second. Drone sources are bounded to 3840 tiles and ballistic sites to 8192. Only explicit administrator/remote test requests use external origins.

Air units retain Factorio unit targeting, ordinary weapon damage and propeller animation. They use 64-tile native navigation waypoints. Unknown forward chunks are requested asynchronously; the unit stops until its next waypoint exists, avoiding the native long-path failure across disconnected generated regions. Recon, terminal attacks and return missions retain their own destinations.

## Defense and warnings

Stationary vanilla damage chains are cloned into equivalent ground-only damage families. Normal enemy resistances are copied; drones have complete resistance to those families. Default player and vehicle ammunition remains unchanged. Turret target masks prevent ammunition waste. Fire propagation, tree fire, projectiles, beams and streams retain the cloned family.

ABM launch readiness is independent of the early-warning radar: finite 192-tile range, own-force matching, one interceptor, 10 MJ and a 60-tick cooldown. All ready batteries launch during the same update. Persistent ordnance records drive visible homing flight. A separate deterministic combat RNG resolves one configured hit roll at encounter; a miss flies past and expires. Missile removal stops new shots and cleans up other in-flight rounds without duplicate effects.

Ballistic motion uses p(t)=0.06t+0.94t^2 and duration=max(45 seconds,distance/24). Each tick updates position, raised visual position, shadow, sound and smoke. Existing pre-upgrade flights retain their old duration and interpolation. Detected threats publish finite radar signals immediately; 384-tile drone and 2048-tile ballistic coverage is combined with a last-60-seconds ETA gate. Unsupported attacks have short-range terminal warnings. Incoming compass bearing is measured from target toward attacker.

Natural ballistics require day20, evolution0.35 and a 30-minute preparation deadline after chemical science becomes researched. The dusk scheduler then selects a real launch site. The ABM technology is not itself an eligibility condition.

## State and presentation

Schema5 adds projectiles, battery cooldowns, independent combat RNG, warning history and per-force preparation deadlines without replacing old active threats or schedules. Short-lived render objects have explicit cleanup. Historical warning diagnostics expire after ten minutes once the event ends.

Development metadata lives in `info.json.in`. This source directory is itself under the user's Factorio mods directory and its name is not a valid installed mod name. Build and test tools copy the template to `info.json` only in their canonical output directories, preventing duplicate/invalid mod discovery during normal gameplay.

All entities use Blender meshes with fixed orthographic camera and world light, alpha-safe packing, independent assembly shadows and mechanical animation. Recorded-source audio is processed into positional loops and one-shots; global warning delivery and personal mute remain independent of radar circuit modes. Source provenance ships in ASSET_LICENSES.md.
