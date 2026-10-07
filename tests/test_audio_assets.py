import hashlib
import json
import math
from pathlib import Path

import numpy as np
import pytest
import soundfile as sf
from scipy.signal import welch

from tools.process_audio import SOUND_SPECS, audit_ogg, load_sources, render_sound, validate_metrics


ROOT = Path(__file__).resolve().parents[1]

EXPECTED = {
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


def test_recorded_audio_manifest_is_complete():
    assert set(SOUND_SPECS) == EXPECTED
    assert {path.name for path in (ROOT / "sound").glob("*.ogg")} == EXPECTED


@pytest.mark.parametrize("name", sorted(EXPECTED))
def test_decoded_audio_meets_runtime_quality_contract(name):
    spec = SOUND_SPECS[name]
    metrics = audit_ogg(ROOT / "sound" / name)
    validate_metrics(name, spec, metrics)
    assert all(math.isfinite(value) for value in vars(metrics).values())
    assert metrics.peak_dbfs <= -1
    assert metrics.true_peak_dbfs <= -1
    assert metrics.rms_dbfs <= spec.target_rms_dbfs + 1
    assert metrics.rms_dbfs >= spec.target_rms_dbfs - 5
    if spec.loop and name != "ballistic-warning.ogg":
        # A zero-valued fade at the wrap would pass a sample-delta-only check.
        assert 0.3 <= metrics.edge_rms_ratio <= 2.5
    elif not spec.loop:
        samples, rate = sf.read(ROOT / "sound" / name)
        assert np.sqrt(np.mean(samples[-round(rate * 0.02):] ** 2)) < 0.015


def test_every_recording_has_verified_redistribution_provenance():
    manifest = json.loads((ROOT / "assets/audio-source/manifest.json").read_text(encoding="utf-8"))
    sources = manifest["sources"]
    used = {layer.source for spec in SOUND_SPECS.values() for layer in spec.layers}
    assert used == set(sources)
    assert len(sources) >= 8
    license_text = (ROOT / "ASSET_LICENSES.md").read_text(encoding="utf-8")
    for source in sources.values():
        assert source["license"] == "CC0-1.0"
        assert source["source_type"] == "recording"
        assert source["author"] and source["title"] and source["license_evidence"]
        assert source["source_url"].startswith("https://")
        assert source["download_url"].startswith("https://")
        assert source["license_url"] == "https://creativecommons.org/publicdomain/zero/1.0/"
        assert hashlib.sha256((ROOT / "assets/audio-source" / source["filename"]).read_bytes()).hexdigest() == source["sha256"]
        assert source["source_url"] in license_text
        assert source["sha256"] in license_text


def test_build_manifest_matches_runtime_files_and_source_lineage():
    build = json.loads((ROOT / "assets/audio-build.json").read_text(encoding="utf-8"))
    sources = json.loads((ROOT / "assets/audio-source/manifest.json").read_text(encoding="utf-8"))["sources"]
    assert set(build["assets"]) == EXPECTED
    hashes = set()
    for name, entry in build["assets"].items():
        digest = hashlib.sha256((ROOT / "sound" / name).read_bytes()).hexdigest()
        assert digest == entry["sha256"]
        hashes.add(digest)
        for key, source_hash in entry["source_sha256"].items():
            assert source_hash == sources[key]["sha256"]
        assert name in (ROOT / "ASSET_LICENSES.md").read_text(encoding="utf-8")
    assert len(hashes) == len(EXPECTED)


@pytest.fixture(scope="module")
def recorded_sources():
    return load_sources(ROOT)[1]


@pytest.mark.parametrize("name", ["drone-strike-loop.ogg", "flak-shot.ogg", "ballistic-launch.ogg", "ballistic-warning.ogg", "air-raid-siren.ogg", "wreck-impact.ogg", "radar-hum-loop.ogg", "airfield-machinery-loop.ogg", "ballistic-site-machinery-loop.ogg"])
def test_shipped_audio_matches_recorded_source_processing(name, recorded_sources):
    expected = render_sound(SOUND_SPECS[name], recorded_sources)
    actual, rate = sf.read(ROOT / "sound" / name)
    assert len(expected) == len(actual)
    # Allow Vorbis quantization while rejecting unrelated replacement material.
    similarity = np.dot(expected, actual) / np.sqrt(np.dot(expected, expected) * np.dot(actual, actual))
    assert similarity > 0.985


def test_drone_and_machinery_families_have_distinct_registers():
    metrics = {name: audit_ogg(ROOT / "sound" / name) for name in EXPECTED}
    recon = metrics["drone-recon-loop.ogg"].spectral_centroid_hz
    strike = metrics["drone-strike-loop.ogg"].spectral_centroid_hz
    heavy = metrics["drone-heavy-loop.ogg"].spectral_centroid_hz
    assert recon > strike * 1.15
    assert strike > heavy * 1.25
    assert metrics["airfield-machinery-loop.ogg"].rms_dbfs < metrics["drone-strike-loop.ogg"].rms_dbfs - 5
    assert metrics["radar-hum-loop.ogg"].rms_dbfs < -26


def test_ballistic_warning_has_a_different_timbre_and_cadence():
    siren = audit_ogg(ROOT / "sound/air-raid-siren.ogg")
    warning = audit_ogg(ROOT / "sound/ballistic-warning.ogg")
    assert warning.spectral_centroid_hz > siren.spectral_centroid_hz * 2
    silence_fractions = []
    for name in ["air-raid-siren.ogg", "ballistic-warning.ogg"]:
        audio, rate = sf.read(ROOT / "sound" / name)
        frame = round(rate * 0.02)
        envelope = np.sqrt(np.mean(audio[:len(audio) // frame * frame].reshape(-1, frame) ** 2, axis=1))
        silence_fractions.append(np.mean(envelope < envelope.max() * 0.06))
    assert silence_fractions[0] < 0.05
    assert silence_fractions[1] > 0.45


@pytest.mark.parametrize("name", ["radar-hum-loop.ogg", "airfield-machinery-loop.ogg", "ballistic-site-machinery-loop.ogg"])
def test_idle_machinery_is_not_dominated_by_a_single_whining_tone(name):
    samples, rate = sf.read(ROOT / "sound" / name)
    frequencies, power = welch(samples, rate, nperseg=16384)
    # Preserve the low motor rumble; reject dominant tones in the whining register.
    audible_tones = np.flatnonzero(frequencies >= 200)
    center = frequencies[audible_tones[np.argmax(power[audible_tones])]]
    narrow_band = power[np.abs(frequencies - center) < 20].sum() / power.sum()
    assert narrow_band < 0.30, f"Persistent narrow tone dominates {name}: {narrow_band:.1%}"
