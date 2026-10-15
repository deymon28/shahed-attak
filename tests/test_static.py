import json
import hashlib

import pytest
from pathlib import Path

from PIL import Image, ImageChops


ROOT = Path(__file__).resolve().parents[1]

EXPECTED_AUDIO_NAMES = {
    "drone-recon-loop.ogg",
    "drone-strike-loop.ogg",
    "drone-heavy-loop.ogg",
    "drone-flyby.ogg",
    "flak-shot.ogg",
    "flak-burst.ogg",
    "drone-impact.ogg",
    "heavy-impact.ogg",
    "wreck-impact.ogg",
    "fuel-explosion.ogg",
    "warhead-explosion.ogg",
    "ballistic-launch.ogg",
    "ballistic-flight-loop.ogg",
    "ballistic-impact.ogg",
    "intercept-launch.ogg",
    "intercept-burst.ogg",
    "radar-hum-loop.ogg",
    "radar-ping.ogg",
    "airfield-machinery-loop.ogg",
    "ballistic-site-machinery-loop.ogg",
    "air-raid-siren.ogg",
    "ballistic-warning.ogg",
}


def test_required_mod_files_exist():
    required = [
        "info.json.in",
        "settings.lua",
        "data.lua",
        "data-final-fixes.lua",
        "control.lua",
        "locale/en/locale.cfg",
        "locale/ru/locale.cfg",
    ]
    missing = [path for path in required if not (ROOT / path).is_file()]
    assert not missing, f"missing required files: {missing}"
    assert not (ROOT / "info.json").exists(), "Development metadata must not register a second installed mod"


def test_mod_metadata_targets_factorio_2_0_77():
    metadata = json.loads((ROOT / "info.json.in").read_text(encoding="utf-8"))
    assert metadata["name"] == "shahed-attack"
    assert metadata["version"] == "0.7.1"
    assert metadata["factorio_version"] == "2.0"
    assert "base >= 2.0.77" in metadata["dependencies"]


def test_alert_delivery_setting_has_exact_modes_and_default():
    source = (ROOT / "settings.lua").read_text(encoding="utf-8")
    assert 'name = "shahed-attack-alert-delivery"' in source
    assert 'default_value = "both"' in source
    assert 'allowed_values = {"both", "global-sound", "circuit-only"}' in source


def test_global_warning_playback_is_non_positional_and_event_scoped():
    alerts = (ROOT / "scripts/alerts.lua").read_text(encoding="utf-8")
    raids = (ROOT / "scripts/raids.lua").read_text(encoding="utf-8")
    ballistics = (ROOT / "scripts/ballistics.lua").read_text(encoding="utf-8")
    assert "player.play_sound({path=path})" in alerts
    assert "function alerts.flush_sounds" in alerts
    assert "player.play_sound({path = request.sound, position" not in alerts
    assert 'request.alert_type .. "::" .. tostring(request.event_id)' in alerts
    assert "record.event_id" in raids
    assert "missile.id" in ballistics


def test_radar_signal_prototypes_and_hidden_relay_are_defined():
    source = (ROOT / "prototypes/signals.lua").read_text(encoding="utf-8")
    data_lua = (ROOT / "data.lua").read_text(encoding="utf-8")
    assert 'name = "shahed-attack-air-raid-signal"' in source
    assert 'name = "shahed-attack-ballistic-signal"' in source
    assert 'name = "shahed-attack-radar-signal-relay"' in source
    assert "relay.item_slot_count = 2" in source
    assert '"not-on-map"' in source
    assert '"not-selectable-in-game"' in source
    assert 'require("prototypes.signals")' in data_lua


def test_radar_signal_runtime_module_has_required_contract():
    source = (ROOT / "scripts/radar_signals.lua").read_text(encoding="utf-8")
    control = (ROOT / "control.lua").read_text(encoding="utf-8")
    for function_name in ["initialize", "on_entity_created", "on_object_destroyed", "update", "status"]:
        assert f"function radar_signals.{function_name}" in source
    assert "defines.wire_connector_id.circuit_red" in source
    assert "defines.wire_connector_id.circuit_green" in source
    assert "section.set_slot(1" in source
    assert "section.set_slot(2" in source
    assert "600" in source
    assert 'require("scripts.radar_signals")' in control


def test_alert_and_circuit_scenarios_and_speaker_docs_exist():
    for name in ["integration-alert-delivery", "integration-radar-circuit"]:
        assert (ROOT / "scenarios" / name / "control.lua").is_file()
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    assert "programmable speaker" in readme.lower()
    assert "shahed-attack-air-raid-signal" in readme
    assert "shahed-attack-ballistic-signal" in readme


def test_audio_prototypes_and_continuous_sources_are_wired():
    sounds = (ROOT / "prototypes/sounds.lua").read_text(encoding="utf-8")
    enemies = (ROOT / "prototypes/enemies.lua").read_text(encoding="utf-8")
    defense = (ROOT / "prototypes/defense.lua").read_text(encoding="utf-8")
    data_lua = (ROOT / "data.lua").read_text(encoding="utf-8")
    assert 'require("prototypes.sounds")' in data_lua
    assert 'name = "shahed-attack-ballistic-sound-source"' in sounds
    for asset in EXPECTED_AUDIO_NAMES:
        assert asset in sounds or asset in enemies or asset in defense
    assert "working_sound" in enemies
    assert "max_sounds_per_prototype" in enemies
    assert "working_sound" in defense


def test_each_wreck_outcome_has_positional_impact_audio():
    effects = (ROOT / "prototypes/effects.lua").read_text(encoding="utf-8")
    assert "wreck-impact.ogg" in effects
    assert "fuel-explosion.ogg" in effects
    assert "warhead-explosion.ogg" in effects


def test_ballistic_cleanup_destroys_valid_moving_sound_source():
    source = (ROOT / "scripts/ballistics.lua").read_text(encoding="utf-8")
    assert "missile.sound_source and missile.sound_source.valid" in source
    assert "missile.sound_source.destroy()" in source


def test_audio_runtime_scenario_exists():
    assert (ROOT / "scenarios/integration-audio-prototypes/control.lua").is_file()


def test_public_runtime_modules_are_present():
    required = [
        "scripts/state.lua",
        "scripts/director.lua",
        "scripts/raids.lua",
        "scripts/ballistics.lua",
        "scripts/defense.lua",
        "scripts/alerts.lua",
        "scripts/commands.lua",
    ]
    missing = [path for path in required if not (ROOT / path).is_file()]
    assert not missing, f"missing runtime modules: {missing}"


def test_original_runtime_art_is_present_and_valid():
    expected_sizes = {
        "graphics/entity/recon-drone-sheet.png": (72 * 16, 72 * 8),
        "graphics/entity/strike-drone-sheet.png": (80 * 16, 80 * 8),
        "graphics/entity/heavy-drone-sheet.png": (96 * 16, 96 * 8),
        "graphics/entity/recon-drone-shadow-sheet.png": (72 * 16, 72 * 8),
        "graphics/entity/strike-drone-shadow-sheet.png": (80 * 16, 80 * 8),
        "graphics/entity/heavy-drone-shadow-sheet.png": (96 * 16, 96 * 8),
        "graphics/entity/airfield-base.png": (320, 320),
        "graphics/entity/airfield-shadow.png": (640, 320),
        "graphics/entity/airfield-overlay-sheet.png": (320 * 4, 320 * 4),
        "graphics/entity/ballistic-site-base.png": (320, 320),
        "graphics/entity/ballistic-site-shadow.png": (640, 320),
        "graphics/entity/ballistic-site-overlay-sheet.png": (320 * 4, 320 * 4),
        "graphics/entity/ballistic-site-launch-sheet.png": (320 * 5, 320 * 4),
        "graphics/entity/early-warning-radar-sheet.png": (192 * 8, 192 * 4),
        "graphics/entity/early-warning-radar-shadow-sheet.png": (384 * 8, 192 * 4),
        "graphics/entity/radar-alert-overlay-sheet.png": (192 * 4, 192 * 3),
        "graphics/entity/early-warning-radar-sheet.png": (192 * 8, 192 * 4),
        "graphics/entity/ballistic-missile.png": (128, 128),
        "graphics/icons/flak-magazine.png": (64, 64),
        "graphics/icons/interceptor.png": (64, 64),
    }
    for relative_path, expected_size in expected_sizes.items():
        path = ROOT / relative_path
        assert path.is_file(), f"missing generated asset: {relative_path}"
        with Image.open(path) as image:
            assert image.size == expected_size
            assert image.mode == "RGBA"
            assert image.getchannel("A").getbbox() is not None


def test_drone_sheet_contains_real_animation_frames():
    with Image.open(ROOT / "graphics/entity/strike-drone-sheet.png") as image:
        first = image.crop((0, 0, 80, 80))
        animated = image.crop((80, 0, 160, 80))
        assert ImageChops.difference(first, animated).getbbox() is not None


def test_radar_sheet_contains_visible_scanning_animation():
    with Image.open(ROOT / "graphics/entity/early-warning-radar-sheet.png") as image:
        first = image.crop((0, 0, 192, 192))
        animated = image.crop((192, 0, 384, 192))
        assert ImageChops.difference(first, animated).getbbox() is not None


def test_visual_overlay_runtime_contract_and_obsolete_art_removal():
    visuals = (ROOT / "prototypes/visuals.lua").read_text(encoding="utf-8")
    runtime = (ROOT / "scripts/visual_effects.lua").read_text(encoding="utf-8")
    data_lua = (ROOT / "data.lua").read_text(encoding="utf-8")
    control = (ROOT / "control.lua").read_text(encoding="utf-8")
    for name in [
        "shahed-attack-airfield-overlay",
        "shahed-attack-ballistic-site-overlay",
        "shahed-attack-ballistic-site-launch",
        "shahed-attack-radar-alert",
    ]:
        assert name in visuals
    for function_name in [
        "initialize",
        "on_entity_created",
        "on_object_destroyed",
        "set_radar_alert",
        "play_ballistic_launch",
        "status",
    ]:
        assert f"function visual_effects.{function_name}" in runtime
    assert 'require("prototypes.visuals")' in data_lua
    assert 'require("scripts.visual_effects")' in control
    for obsolete in ["airfield.png", "ballistic-site.png", "early-warning-radar.png"]:
        assert not (ROOT / "graphics" / "entity" / obsolete).exists()


def test_aa_and_abm_replace_every_inherited_visual_state():
    defense = (ROOT / "prototypes/defense.lua").read_text(encoding="utf-8")
    for field in [
        "folded_animation",
        "preparing_animation",
        "prepared_animation",
        "attacking_animation",
        "folding_animation",
        "graphics_set",
    ]:
        assert defense.count(f".{field} =") >= 2, field
    assert "__base__/graphics/entity/gun-turret/" not in defense
    for asset_name in [
        "aa-turret-base.png",
        "aa-turret-base-shadow.png",
        "aa-turret-head-prepared.png",
        "aa-turret-head-attacking.png",
        "abm-battery-base.png",
        "abm-battery-base-shadow.png",
        "abm-battery-head-prepared.png",
        "abm-battery-launch-sheet.png",
    ]:
        assert (ROOT / "graphics" / "entity" / asset_name).is_file(), asset_name
    assert not (ROOT / "graphics" / "entity" / "aa-turret.png").exists()
    assert not (ROOT / "graphics" / "entity" / "abm-battery.png").exists()
    with Image.open(ROOT / "graphics/icons/flak-magazine.png") as flak:
        with Image.open(ROOT / "graphics/icons/interceptor.png") as interceptor:
            assert ImageChops.difference(flak.convert("RGBA"), interceptor.convert("RGBA")).getbbox() is not None


def test_visual_runtime_scenarios_and_asset_record_are_present():
    for name in ["integration-visual-prototypes", "integration-wreck-completion"]:
        assert (ROOT / "scenarios" / name / "control.lua").is_file()
    documentation = (ROOT / "docs/ASSETS.md").read_text(encoding="utf-8")
    for phrase in [
        "12/255 alpha threshold",
        "16x8 aircraft",
        "8x12 wrecks",
        "64 turret directions",
        "build/hybrid-overhaul",
    ]:
        assert phrase in documentation


def test_ballistic_motion_scenario_exists():
    assert (ROOT / "scenarios/integration-ballistic-motion/control.lua").is_file()


def test_migration_artifacts_and_immutable_031_fixture_exist():
    assert (ROOT / "migrations/0.4.0.lua").is_file()
    assert (ROOT / "tests/migration.ps1").is_file()
    build = (ROOT / "tools/build.ps1").read_text(encoding="utf-8")
    assert '"migrations"' in build
    fixture = ROOT / "dist/shahed-attack_0.3.1.zip"
    if not fixture.is_file():
        pytest.skip("release archives are kept locally in dist/, not in the repository")
    assert hashlib.sha256(fixture.read_bytes()).hexdigest() == "8fd2499f64ed50aec85633aabcf260e89a84a865c43087f2bd747b65590e5a73"


def test_readme_documents_the_current_interfaces():
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    for phrase in [
        "0.7.1",
        "both",
        "global-sound",
        "circuit-only",
        "shahed-attack-air-raid-signal",
        "shahed-attack-ballistic-signal",
        "programmable speaker",
        "Anti-air wagon",
        "Missile-defense wagon",
        "FACTORIO_EXE",
        "tests\\run-all.ps1",
    ]:
        assert phrase in readme


def test_full_runner_lists_all_runtime_scenarios_once():
    runner_path = ROOT / "tests/run-all.ps1"
    assert runner_path.is_file()
    source = runner_path.read_text(encoding="utf-8")
    scenarios = [
        "integration-air-war-v5",
        "integration-ground-turrets",
        "integration-natural-sources",
        "integration-distant-flight",
        "integration-test",
        "integration-targeting",
        "integration-force",
        "integration-force-merge",
        "integration-remote-before-init",
        "integration-raid-cap",
        "integration-navigation",
        "integration-formation",
        "integration-recon",
        "integration-flak-accuracy",
        "integration-drone-impact",
        "integration-crash",
        "integration-target-loss",
        "integration-invalid-target",
        "integration-ballistic-flight",
        "integration-alert-delivery",
        "integration-radar-circuit",
        "integration-audio-prototypes",
        "integration-visual-prototypes",
        "integration-wreck-completion",
        "integration-ballistic-motion",
    ]
    for scenario in scenarios:
        assert source.count(f'"{scenario}"') == 1, scenario


def test_prototypes_reference_original_runtime_art():
    enemies = (ROOT / "prototypes/enemies.lua").read_text(encoding="utf-8")
    defense = (ROOT / "prototypes/defense.lua").read_text(encoding="utf-8")
    categories = (ROOT / "prototypes/categories.lua").read_text(encoding="utf-8")
    assert "__shahed-attack__/graphics/entity/" in enemies
    for asset_stem in ["recon-drone", "strike-drone", "heavy-drone", "airfield", "ballistic-site"]:
        assert f'"{asset_stem}"' in enemies
    assert "frame_count = 8" in enemies
    assert "line_length = 16" in enemies
    assert 'sprite_name .. "-shadow-sheet.png"' in enemies
    assert "__shahed-attack__/graphics/icons/flak-magazine.png" in defense
    assert "__shahed-attack__/graphics/icons/interceptor.png" in defense
    assert "__shahed-attack__/graphics/entity/ballistic-missile.png" in categories


def test_drone_speeds_are_visibly_slower_than_vanilla_biters():
    enemies = (ROOT / "prototypes/enemies.lua").read_text(encoding="utf-8")
    assert "  0.11," in enemies
    assert "  0.08," in enemies
    assert "  0.06," in enemies
    assert "destroy_when_commands_fail = false" in enemies
    assert "allow_try_return_to_spawner = false" in enemies


def test_original_warning_sounds_are_present_and_referenced():
    sounds = (ROOT / "prototypes/sounds.lua").read_text(encoding="utf-8")
    for name in ["air-raid-siren.ogg", "ballistic-warning.ogg", "intercept-launch.ogg"]:
        path = ROOT / "sound" / name
        assert path.is_file(), f"missing original sound: {name}"
        assert path.stat().st_size > 1000
        assert name in sounds
