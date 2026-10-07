"""English and Russian locale files must expose the same complete key set."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def parse_locale(path: Path) -> dict[tuple[str, str], str]:
    section = None
    result: dict[tuple[str, str], str] = {}
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith(";") or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
            continue
        assert section, f"key before section at {path}:{line_number}"
        assert "=" in line, f"malformed locale line at {path}:{line_number}"
        key, value = line.split("=", 1)
        pair = (section, key.strip())
        assert pair not in result, f"duplicate locale key {pair} in {path}"
        assert value.strip(), f"empty locale value {pair} in {path}"
        result[pair] = value.strip()
    return result


def test_english_and_russian_locale_have_exact_key_parity():
    english = parse_locale(ROOT / "locale/en/locale.cfg")
    russian = parse_locale(ROOT / "locale/ru/locale.cfg")
    assert english.keys() == russian.keys()


def test_required_alert_and_signal_locale_keys_are_present():
    english = parse_locale(ROOT / "locale/en/locale.cfg")
    required = {
        ("mod-setting-name", "shahed-attack-alert-delivery"),
        ("string-mod-setting", "shahed-attack-alert-delivery-both"),
        ("string-mod-setting", "shahed-attack-alert-delivery-global-sound"),
        ("string-mod-setting", "shahed-attack-alert-delivery-circuit-only"),
        ("virtual-signal-name", "shahed-attack-air-raid-signal"),
        ("virtual-signal-name", "shahed-attack-ballistic-signal"),
    }
    assert required <= english.keys()
