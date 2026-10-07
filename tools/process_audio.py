"""Build runtime audio from checksum-pinned CC0 recordings, without oscillators."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
import subprocess
import tempfile
from dataclasses import asdict, dataclass
from fractions import Fraction
from pathlib import Path

import numpy as np
import scipy
import soundfile as sf
from scipy.signal import butter, resample_poly, sosfiltfilt, welch

SAMPLE_RATE = 48_000
LOOP_OVERLAP = 0.6


@dataclass(frozen=True)
class Layer:
    source: str
    start: float
    duration: float
    speed: float = 1.0
    gain: float = 1.0
    highpass: float = 45.0
    lowpass: float = 8000.0
    offset: float = 0.0
    attack: float = 0.004
    release: float = 0.14
    reject_tones: tuple[float, ...] = ()


@dataclass(frozen=True)
class SoundSpec:
    duration: float
    loop: bool
    target_rms_dbfs: float
    layers: tuple[Layer, ...]
    description: str


@dataclass(frozen=True)
class AudioMetrics:
    sample_rate: int
    channels: int
    duration: float
    peak_dbfs: float
    true_peak_dbfs: float
    rms_dbfs: float
    dc_offset: float
    clipped_samples: int
    loop_seam_delta: float
    edge_rms_ratio: float
    spectral_centroid_hz: float


SOUND_SPECS = {
    "drone-recon-loop.ogg": SoundSpec(4.0, True, -20.5, (Layer("rc-engine", 5.0, 4.6, 1.24, 1, 130, 4700),), "Higher, lean gasoline-propeller buzz with natural RPM variation."),
    "drone-strike-loop.ogg": SoundSpec(4.8, True, -20, (Layer("rc-engine", 6.1, 5.4, 0.96, 1, 65, 4300),), "Close midrange gasoline-propeller engine with irregular mechanical texture."),
    "drone-heavy-loop.ogg": SoundSpec(5.2, True, -19.5, (Layer("rc-engine", 5.6, 5.8, 0.72, 0.86, 40, 3000), Layer("propeller-plane", 6, 5.8, 0.77, 0.3, 35, 1050)), "Slower engine and low recorded aircraft layer with darker exhaust tone."),
    "drone-flyby.ogg": SoundSpec(3.0, False, -20, (Layer("rc-engine", 7.6, 3, 1, 1, 70, 5500, attack=0.4, release=0.7),), "Natural close pass and receding RPM from the recorded RC aircraft."),
    "flak-shot.ogg": SoundSpec(0.5, False, -19, (Layer("gunshot", 11.656, 0.5, 0.82, 1, 80, 8500, attack=0.001), Layer("demolition", 2.15, 0.35, 1.15, 0.17, 50, 350)), "Recorded firearm crack with a restrained low demolition thump."),
    "flak-burst.ogg": SoundSpec(0.95, False, -19.5, tuple(Layer("gunshot", start, 0.45, speed, gain, 100, 7800, offset, 0.001, 0.15) for start, speed, gain, offset in [(11.656, 0.86, 1, 0), (6.16, 0.9, 0.88, 0.13), (16.22, 0.84, 0.94, 0.27), (20.69, 0.92, 0.82, 0.41)]), "Four different recorded shots with small timing and pitch differences."),
    "drone-impact.ogg": SoundSpec(1.8, False, -18.5, (Layer("demolition", 2.145, 1.8, 1.15, 1, 60, 6500), Layer("metal-crash", 0.49, 0.78, 1.1, 0.17, 600, 7000, 0.09)), "Compact real blast and short metal-debris tail."),
    "heavy-impact.ogg": SoundSpec(2.8, False, -18, (Layer("demolition", 2.145, 2.8, 0.82, 1, 35, 4600), Layer("metal-crash", 1.22, 1.4, 0.75, 0.2, 300, 4300, 0.18)), "Slower heavy detonation and delayed metal collapse."),
    "wreck-impact.ogg": SoundSpec(1.25, False, -22, (Layer("metal-crash", 0.49, 1.25, 0.86, 1, 120, 6200),), "Metal crash and scrape without an explosive bass layer."),
    "fuel-explosion.ogg": SoundSpec(2.5, False, -19, (Layer("demolition", 2.145, 1.6, 0.95, 0.8, 50, 5200), Layer("rocket", 0.55, 2.15, 0.82, 0.32, 220, 4100, 0.18, 0.07, 0.65)), "Blast followed by a broad recorded combustion roar."),
    "warhead-explosion.ogg": SoundSpec(2.3, False, -18, (Layer("demolition", 2.145, 2.3, 0.72, 1, 30, 6500), Layer("gunshot", 0.496, 0.3, 0.8, 0.12, 950, 8000)), "Deep detonation with a sharp initial pressure crack."),
    "ballistic-launch.ogg": SoundSpec(2.5, False, -18.5, (Layer("rocket", 19.17, 2.5, 0.82, 1, 35, 6300, attack=0.01, release=0.35),), "Recorded rocket ignition and sustained exhaust, modestly pitched down."),
    "ballistic-flight-loop.ogg": SoundSpec(3.2, True, -23, (Layer("rocket", 20.0, 3.8, 1, 1, 170, 5100),), "Recorded rocket exhaust with a continuous broad-band flight rush."),
    "ballistic-impact.ogg": SoundSpec(4.0, False, -17.5, (Layer("demolition", 2.145, 4, 0.61, 1, 28, 4200), Layer("metal-crash", 0.49, 2.4, 0.64, 0.23, 200, 5200, 0.32), Layer("demolition", 3, 2.8, 0.76, 0.16, 40, 900, 1.0)), "Largest low detonation, delayed debris, and long pressure decay."),
    "intercept-launch.ogg": SoundSpec(1.2, False, -20, (Layer("rocket", 7.22, 1.2, 1.28, 1, 180, 8500, attack=0.003, release=0.25),), "Tight higher-pitched rocket ignition with a short exhaust tail."),
    "intercept-burst.ogg": SoundSpec(1.0, False, -20, (Layer("demolition", 2.145, 1, 1.52, 1, 190, 8000),), "Fast bright airburst retaining the recorded explosion's crackle."),
    "radar-hum-loop.ogg": SoundSpec(4.0, True, -29, (Layer("compressor", 3.2, 4.6, 1.08, 1, 90, 1500, reject_tones=(176.6, 353.2, 706.4, 1059.6)),), "Quiet radar drive texture with persistent compressor whine removed."),
    "radar-ping.ogg": SoundSpec(0.65, False, -25, (Layer("alarm", 0.23, 0.11, 0.76, 1, 500, 3000, attack=0.006, release=0.04), Layer("alarm", 0.23, 0.11, 0.76, 0.17, 500, 2800, 0.16, 0.006, 0.06), Layer("alarm", 0.23, 0.11, 0.76, 0.06, 500, 2400, 0.29, 0.006, 0.06)), "A recorded buzzer pulse with two quiet filtered echoes."),
    "airfield-machinery-loop.ogg": SoundSpec(6.0, True, -27, (Layer("compressor", 1.4, 6.6, 0.88, 1, 50, 2800, reject_tones=(176.6, 353.2, 706.4, 1059.6)),), "Recorded mechanical texture with sustained compressor tones removed."),
    "ballistic-site-machinery-loop.ogg": SoundSpec(6.0, True, -27.5, (Layer("compressor", 5, 6.6, 0.64, 1, 35, 1500, reject_tones=(176.6, 353.2, 706.4, 1059.6)), Layer("metal-crash", 2.15, 0.6, 0.65, 0.015, 140, 1800, 2.1, 0.18, 0.3)), "Slower machinery with the sustained whine removed and subtle mechanism vibration retained."),
    "air-raid-siren.ogg": SoundSpec(6.0, True, -21, (Layer("siren", 21.15, 6.6, 1.17, 1, 170, 3300),), "Real civil-defense siren descending and rising through its mechanical cycle."),
    "ballistic-warning.ogg": SoundSpec(4.5, True, -20.5, tuple(Layer("alarm", 0.23, 0.14, speed, 1, 450, 3800, offset, 0.005, 0.025) for offset, speed in [(0, 0.64), (0.23, 0.64), (0.46, 0.83), (1.5, 0.64), (1.73, 0.64), (1.96, 0.83), (3, 0.64), (3.23, 0.64), (3.46, 0.83), (4.5, 0.64), (4.73, 0.64), (4.96, 0.83)]), "Three groups of three recorded buzzer pulses, with a raised third pulse."),
}


def find_ffmpeg() -> Path:
    binary = shutil.which("ffmpeg")
    if binary is None:
        raise RuntimeError("FFmpeg is required on PATH for Vorbis encoding")
    return Path(binary)


def load_sources(root: Path) -> tuple[dict, dict[str, np.ndarray]]:
    source_root = root / "assets" / "audio-source"
    manifest = json.loads((source_root / "manifest.json").read_text(encoding="utf-8"))
    decoded = {}
    for key, entry in manifest["sources"].items():
        path = source_root / entry["filename"]
        if hashlib.sha256(path.read_bytes()).hexdigest() != entry["sha256"]:
            raise RuntimeError(f"Source checksum mismatch: {key}")
        if entry["license"] != "CC0-1.0":
            raise RuntimeError(f"Unreviewed source license: {key}")
        audio, rate = sf.read(path, dtype="float64", always_2d=True)
        ratio = Fraction(SAMPLE_RATE, rate)
        decoded[key] = resample_poly(audio.mean(axis=1), ratio.numerator, ratio.denominator)
    return manifest, decoded


def filtered(audio: np.ndarray, highpass: float, lowpass: float) -> np.ndarray:
    return sosfiltfilt(butter(3, [highpass, lowpass], btype="bandpass", fs=SAMPLE_RATE, output="sos"), audio)


def fade(audio: np.ndarray, attack: float, release: float) -> np.ndarray:
    audio = audio.copy()
    a = min(round(attack * SAMPLE_RATE), len(audio) // 2)
    r = min(round(release * SAMPLE_RATE), len(audio) // 2)
    if a:
        audio[:a] *= np.linspace(0, 1, a) ** 0.8
    if r:
        audio[-r:] *= np.linspace(1, 0, r) ** 1.4
    return audio


def render_layer(layer: Layer, sources: dict[str, np.ndarray], loop: bool) -> np.ndarray:
    audio = sources[layer.source]
    start = round(layer.start * SAMPLE_RATE)
    count = round(layer.duration * layer.speed * SAMPLE_RATE)
    if start + count > len(audio):
        raise ValueError(f"Source segment exceeds recording: {layer}")
    speed = Fraction(layer.speed).limit_denominator(1000)
    audio = resample_poly(audio[start:start + count], speed.denominator, speed.numerator)
    audio = filtered(audio, layer.highpass, layer.lowpass)
    for source_frequency in layer.reject_tones:
        center = source_frequency * layer.speed
        audio = sosfiltfilt(butter(3, [center * 0.9, center * 1.1], btype="bandstop",
                                  fs=SAMPLE_RATE, output="sos"), audio)
    rms = float(np.sqrt(np.mean(audio * audio)))
    if rms < 1e-6:
        raise ValueError(f"Silent source segment: {layer}")
    audio *= 0.16 / rms
    if not loop or layer.duration < 2:
        audio = fade(audio, layer.attack, layer.release)
    return audio * layer.gain


def crossfade_loop(audio: np.ndarray, duration: float) -> np.ndarray:
    count = round(duration * SAMPLE_RATE)
    overlap = len(audio) - count
    if overlap < 2:
        raise ValueError("A loop needs source audio beyond the requested duration")
    weight = (1 - np.cos(np.linspace(0, np.pi, overlap))) / 2
    blend = audio[count:] * (1 - weight) + audio[:overlap] * weight
    return np.concatenate((audio[overlap:count], blend))


def render_sound(spec: SoundSpec, sources: dict[str, np.ndarray]) -> np.ndarray:
    duration = spec.duration + (LOOP_OVERLAP if spec.loop else 0)
    result = np.zeros(round(duration * SAMPLE_RATE), dtype=np.float64)
    for layer in spec.layers:
        sample = render_layer(layer, sources, spec.loop)
        offset = round(layer.offset * SAMPLE_RATE)
        count = min(len(sample), len(result) - offset)
        result[offset:offset + count] += sample[:count]
    result = crossfade_loop(result, spec.duration) if spec.loop else fade(result, 0.0015, min(0.16, spec.duration / 6))
    result -= result.mean()
    rms = float(np.sqrt(np.mean(result * result)))
    result *= min(10 ** (spec.target_rms_dbfs / 20) / rms, 10 ** (-3.0 / 20) / np.max(np.abs(result)))
    if spec.loop:
        # Place the wrap at a naturally smooth transition, without inserting silence.
        seam = int(np.argmin(np.abs(np.diff(result[:SAMPLE_RATE])))) + 1
        result = np.roll(result, -seam)
    else:
        result[0] = result[-1] = 0
    return result


def db(value: float) -> float:
    return 20 * math.log10(max(float(value), 1e-12))


def audit_ogg(path: Path, ffmpeg: Path | None = None) -> AudioMetrics:
    audio, rate = sf.read(path, dtype="float64", always_2d=True)
    mono = audio.mean(axis=1)
    rms = float(np.sqrt(np.mean(mono * mono)))
    edge = min(round(0.025 * rate), len(mono) // 2)
    edge_rms = float(np.sqrt(np.mean(np.concatenate((mono[:edge], mono[-edge:])) ** 2)))
    frequencies, power = welch(mono, fs=rate, nperseg=min(8192, len(mono)))
    return AudioMetrics(rate, audio.shape[1], len(mono) / rate, db(np.max(np.abs(audio))), db(np.max(np.abs(resample_poly(audio, 4, 1, axis=0)))), db(rms), float(mono.mean()), int(np.count_nonzero(np.abs(audio) >= 1)), float(abs(mono[-1] - mono[0])), edge_rms / max(rms, 1e-12), float(np.sum(frequencies * power) / max(np.sum(power), 1e-12)))


def validate_metrics(name: str, spec: SoundSpec, metrics: AudioMetrics) -> None:
    if metrics.sample_rate != SAMPLE_RATE or metrics.channels != 1:
        raise RuntimeError(f"Invalid stream format: {name}")
    if abs(metrics.duration - spec.duration) > 1 / SAMPLE_RATE:
        raise RuntimeError(f"Unexpected decoded duration: {name}")
    if metrics.true_peak_dbfs > -1 or metrics.clipped_samples or abs(metrics.dc_offset) > 0.002:
        raise RuntimeError(f"Invalid decoded levels: {name}: {metrics}")
    if not -36 <= metrics.rms_dbfs <= -14:
        raise RuntimeError(f"Inaudible or excessively loud asset: {name}: {metrics.rms_dbfs}")
    if spec.loop and metrics.loop_seam_delta > 0.035:
        raise RuntimeError(f"Loop seam discontinuity: {name}: {metrics.loop_seam_delta}")


def generate_all(root: Path, ffmpeg: Path) -> list[Path]:
    manifest, sources = load_sources(root)
    sound_root = root / "sound"
    sound_root.mkdir(exist_ok=True)
    assets = {}
    with tempfile.TemporaryDirectory(prefix="shahed-recorded-audio-") as directory:
        wav = Path(directory) / "mix.wav"
        for name, spec in SOUND_SPECS.items():
            sf.write(wav, render_sound(spec, sources), SAMPLE_RATE, subtype="PCM_24")
            path = sound_root / name
            subprocess.run([str(ffmpeg), "-hide_banner", "-loglevel", "error", "-y", "-i", str(wav), "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact", "-c:a", "libvorbis", "-q:a", "7", str(path)], check=True)
            metrics = audit_ogg(path)
            validate_metrics(name, spec, metrics)
            assets[name] = {"sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "bytes": path.stat().st_size, "spec": asdict(spec), "metrics": asdict(metrics), "source_sha256": {layer.source: manifest["sources"][layer.source]["sha256"] for layer in spec.layers}}
            print(f"PASS {name}: {metrics.duration:.2f}s RMS={metrics.rms_dbfs:.1f}dBFS true-peak={metrics.true_peak_dbfs:.1f}dBFS", flush=True)
    report = {"schema_version": 1, "pipeline": "Recorded CC0 sources, edited and layered; no synthetic oscillator/noise generation.", "sample_rate": SAMPLE_RATE, "versions": {"numpy": np.__version__, "scipy": scipy.__version__, "soundfile": sf.__version__, "libsndfile": sf.__libsndfile_version__, "ffmpeg": subprocess.check_output([str(ffmpeg), "-version"], text=True).splitlines()[0]}, "assets": assets}
    (root / "assets" / "audio-build.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return [sound_root / name for name in SOUND_SPECS]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--audit-only", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve()
    if args.audit_only:
        for name, spec in SOUND_SPECS.items():
            metrics = audit_ogg(root / "sound" / name)
            validate_metrics(name, spec, metrics)
            print(f"PASS {name}: RMS={metrics.rms_dbfs:.1f}dBFS true-peak={metrics.true_peak_dbfs:.1f}dBFS")
    else:
        generate_all(root, find_ffmpeg())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
