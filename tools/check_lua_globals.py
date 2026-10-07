"""Report undeclared global reads and any global writes in the mod's Lua code.

Uses the `luac` bytecode listing (GETTABUP/SETTABUP on _ENV), so it needs only
a stock Lua 5.4 installation. Exit code 1 when a problem is found.
"""
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCES = ["control.lua", "settings.lua", "data.lua", "data-final-fixes.lua",
           "prototypes", "scripts", "migrations"]

ALLOWED = {
    # Lua standard library available in Factorio
    "assert", "error", "ipairs", "next", "pairs", "pcall", "print", "rawequal", "rawget", "rawlen",
    "rawset", "require", "select", "setmetatable", "getmetatable", "tonumber", "tostring", "type",
    "xpcall", "math", "string", "table", "bit32", "unpack", "load", "debug",
    # Factorio runtime and data stage
    "game", "script", "storage", "settings", "defines", "rendering", "remote", "commands", "log",
    "helpers", "prototypes", "localised_print", "serpent", "data", "mods", "table_size",
}

PATTERN = re.compile(r"\b(GETTABUP|SETTABUP)\b.*?_ENV \"([A-Za-z_][A-Za-z0-9_]*)\"")


def lua_files():
    for entry in SOURCES:
        path = ROOT / entry
        if path.is_file():
            yield path
        else:
            yield from sorted(path.rglob("*.lua"))


def main():
    luac = sys.argv[1] if len(sys.argv) > 1 else "luac"
    problems = []
    for path in lua_files():
        listing = subprocess.run([luac, "-p", "-l", "-l", str(path)], capture_output=True, text=True)
        if listing.returncode != 0:
            problems.append(f"{path.relative_to(ROOT)}: {listing.stderr.strip()}")
            continue
        for operation, name in PATTERN.findall(listing.stdout):
            if operation == "SETTABUP":
                problems.append(f"{path.relative_to(ROOT)}: writes global '{name}'")
            elif name not in ALLOWED:
                problems.append(f"{path.relative_to(ROOT)}: reads undeclared global '{name}'")
    for problem in sorted(set(problems)):
        print(problem)
    if problems:
        return 1
    print("PASS: no undeclared globals")
    return 0


if __name__ == "__main__":
    sys.exit(main())
