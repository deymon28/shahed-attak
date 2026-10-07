"""Write audio provenance, measured QA documentation and a local audition page."""
from __future__ import annotations

import html
import json
from pathlib import Path


def write_reports(root: Path) -> None:
    sources = json.loads((root / "assets/audio-source/manifest.json").read_text(encoding="utf-8"))["sources"]
    build = json.loads((root / "assets/audio-build.json").read_text(encoding="utf-8"))
    assets = build["assets"]
    license_lines = [
        "# Asset licenses", "", "## Recorded audio", "",
        "All 22 runtime files in `sound/` are edited adaptations of the nine CC0 recordings listed below. All sources permit modification, redistribution and commercial use under [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/). Credits are retained voluntarily. No endorsement by the recordists is implied.", "",
        "The audio processing contributions are also dedicated to CC0 1.0. This statement covers the sound recordings and audio edits; it does not relicense the mod's code or other assets.", "",
        "Source access and license labels were verified on 2026-09-05. Freesound inputs are the openly linked high-quality MP3 previews, which carry the source recording's CC0 license. Login-protected original downloads were not accessed. BigSoundBank inputs are the author's public MP3 downloads. The source cache and build tools are development materials; only the final OGG files and this attribution file need to ship with the mod.", "",
    ]
    for key, source in sources.items():
        license_lines += [f"### {source['title']}", "", f"- Author: {source['author']}", f"- Source: [{source['title']}]({source['source_url']})", f"- License: [CC0 1.0 Universal]({source['license_url']})", f"- Downloaded recording: [{source['filename']}]({source['download_url']})", f"- Source SHA-256: `{source['sha256']}`", f"- Recording: {source['description']}", ""]
        if "publisher_license_url" in source:
            license_lines += [f"Publisher license confirmation: [BigSoundBank license]({source['publisher_license_url']}).", ""]
    license_lines += ["## Runtime audio transformations", "", "Every sound is converted to mono at 48 kHz, band-pass filtered, level balanced with at least 3 dB of pre-encoding headroom, and encoded as Ogg Vorbis quality 7. One-shots have short fades; sustained loops use a 600 ms overlap crossfade. Source timing, speed, gain, frequency cutoffs and offsets are recorded exactly in `assets/audio-build.json` and `tools/process_audio.py`.", "", "| Runtime file | Sources | Adaptation |", "|---|---|---|"]
    for name, asset in assets.items():
        labels = ", ".join(sources[key]["title"] for key in asset["source_sha256"])
        license_lines.append(f"| `{name}` | {labels} | {asset['spec']['description']} |")
    license_lines += ["", "## Runtime SHA-256 checksums", "", "| File | SHA-256 |", "|---|---|"]
    license_lines += [f"| `{name}` | `{asset['sha256']}` |" for name, asset in assets.items()]
    (root / "ASSET_LICENSES.md").write_text("\n".join(license_lines) + "\n", encoding="utf-8")

    size = sum(asset["bytes"] for asset in assets.values())
    report = ["# Recorded audio report", "", "## Result", "", f"Replaced all 22 synthetic runtime OGG files with effects built from nine licensed real recordings. Runtime audio occupies {size:,} bytes ({size / 1024 / 1024:.2f} MiB). No generated oscillator or noise source is used. Existing sound filenames are preserved.", "", "The RC gasoline-engine recording supplies propeller texture. A second aircraft recording gives the heavy drone a lower body. Shooting-range gunshots, a landmine-demolition recording, metal-crash foley and rocket-launch recordings supply combat sounds. A compressor supplies machinery. A real French civil-defense siren and a recorded electronic buzzer give the two warnings separate timbres and cadences.", "", "## Sources and reproduction", "", "See [ASSET_LICENSES.md](../ASSET_LICENSES.md) for source pages, authors, licenses, download URLs, changes and source/runtime checksums. Development source files are in `assets/audio-source/`; runtime files are in `sound/`. The exact recipes, tool versions and decoded measurements are in `assets/audio-build.json`.", "", "```powershell", "python tools/fetch_audio_sources.py", "python tools/process_audio.py", "python tools/audio_report.py", "python tools/process_audio.py --audit-only", "python -m pytest tests/test_audio_assets.py -q", "```", "", "The fetch step is optional while checksum-valid cached recordings are present. It restores only the pinned public files, fails on a changed download, and requires network access. Rendering and tests are offline. Python dependencies are NumPy, SciPy, SoundFile, requests (downloader only), and pytest (tests only); FFmpeg with libvorbis is required to encode. `tools/generate_sounds.py` forwards to the recorded-source processor for command compatibility.", "", "## Validation", "", "The processor decodes every encoded OGG and rejects clipping, true peaks above -1 dBTP (4x oversampling), DC offset above 0.002, wrong channel/rate/duration, or excessive loop-boundary discontinuity. Tests also check sustained energy across wraps, fading one-shot tails, source hashes, complete redistribution provenance, recorded-source reconstruction, separate motor registers, quiet machinery and distinctly pulsed ballistic warnings.", "", "RMS is an unweighted electrical level, not an integrated loudness or a perceived-loudness score. Spectral and waveform checks support asset QA but do not establish how a busy game mix sounds.", "", "| File | Seconds | RMS dBFS | True peak dBTP | Seam delta |", "|---|---:|---:|---:|---:|"]
    verification_path = root / "assets/audio-validation.json"
    if verification_path.exists():
        verification = json.loads(verification_path.read_text(encoding="utf-8"))
        if verification["runtime_sha256"] == {name: asset["sha256"] for name, asset in assets.items()}:
            report[report.index("## Validation") + 2:report.index("## Validation") + 2] = [
                "Recorded verification on " + verification["date"] + ": " + verification["pytest_result"] + ". All 22 OGG files were byte-identical after a second full build. Cached source checksums and Python compilation also passed.", "",
            ]
    for name, asset in assets.items():
        m = asset["metrics"]
        report.append(f"| `{name}` | {m['duration']:.2f} | {m['rms_dbfs']:.1f} | {m['true_peak_dbfs']:.1f} | {m['loop_seam_delta']:.6f} |")
    report += ["", "## Mixing and integration", "", "Suggested starting prototype volumes: recon 0.40, strike 0.50, heavy 0.62; flyby 0.55; flak shot 0.48 and burst 0.50; normal impact 0.70, heavy 0.82, ballistic 0.90; interception 0.65; radar machinery 0.35, airfield/silo machinery 0.45; radar ping 0.40; siren 0.72 and ballistic warning 0.68. These are starting points for an in-game listening pass, not measured perceptual optima.", "", "Keep the ballistic warning ahead of the general siren when both threats exist. Use positional drone and missile loops, cap simultaneous machinery/flight instances, and give impacts room above the background. Preserve the 6.0-second siren and 4.5-second warning timing. Engine loops are now 4.0/4.8/5.2 seconds; flyby is 3.0 seconds, ballistic flight 3.2 seconds, and machinery 4.0 or 6.0 seconds. The flak one-shot is 0.50 seconds and its four-shot burst is 0.95 seconds; avoid playing both for the same shot sequence. Variation in the flak burst comes from four different recorded shots; runtime random pitch, if added, should remain subtle (roughly +/-3%) to preserve identity.", "", "## Audition and limits", "", "Open [the local audition page](../assets/audio-audition.html) to hear every runtime file and repeat loop boundaries. It references the shipped OGG files directly, so it does not maintain a separate preview mix. Start at a comfortable listening level.", "", "No subjective listening or full gameplay mix approval is claimed in this report: the agent tools could inspect/decode audio and expose playback controls, but did not provide auditory perception. The material was selected from primary recordist descriptions and measured waveforms. Freesound originals require login; this build uses their licensed public MP3 previews, so MP3 source compression remains before the final Vorbis encode. Upsampling to 48 kHz does not restore information absent from those recordings. BigSoundBank's listed direct WAV links returned 404, so the working public MP3s were used. Public Freesound page access later returned 403; additional siren and buzzer sources were obtained directly from BigSoundBank.", ""]
    (root / "docs/AUDIO_REPORT.md").write_text("\n".join(report), encoding="utf-8")
    cards = []
    for name, asset in assets.items():
        spec = asset["spec"]
        loop = " loop" if spec["loop"] else ""
        cards.append(f'<article><h2>{html.escape(name.removesuffix(".ogg"))}</h2><p>{html.escape(spec["description"])}</p><span>{spec["duration"]:.2f} s &middot; {"Loop" if spec["loop"] else "One shot"} &middot; {asset["metrics"]["rms_dbfs"]:.1f} dBFS RMS</span><audio controls preload="none"{loop} src="../sound/{name}"></audio></article>')
    page = '<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Shahed Attack - recorded audio audition</title><style>body{background:#111820;color:#e8edf1;font:16px/1.5 system-ui,sans-serif;max-width:1200px;margin:auto;padding:32px}h1{font-size:32px}h2{font-size:18px;margin:0 0 8px}p{color:#abb8c4}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:18px}article{border:1px solid #36434d;padding:20px;background:#19242d;border-radius:10px}article p{min-height:72px}span{display:block;color:#98cfc0;font-size:13px}audio{width:100%;margin-top:16px}a{color:#9bddcc}button{padding:8px 16px;margin-bottom:20px;background:#c9e6da;border:0;border-radius:6px;font-weight:600}</style><h1>Recorded audio audition</h1><p>22 runtime effects derived from nine CC0 recordings. Loops repeat automatically while playing. Play one sound at a time, then compare it in the game mix.</p><p><a href="../ASSET_LICENSES.md">Source credits and licenses</a> &middot; <a href="../docs/AUDIO_REPORT.md">Measured audio report</a></p><button onclick="document.querySelectorAll(\'audio\').forEach(a=>a.pause())">Stop all sounds</button><main>' + ''.join(cards) + '</main><script>document.querySelectorAll("audio").forEach(a=>{a.volume=.55;a.addEventListener("play",()=>document.querySelectorAll("audio").forEach(b=>{if(b!==a)b.pause()}))})</script></html>'
    (root / "assets/audio-audition.html").write_text(page, encoding="utf-8")
    print(f"Wrote credits, report and audition page for {len(assets)} assets")


if __name__ == "__main__":
    write_reports(Path(__file__).resolve().parents[1])
