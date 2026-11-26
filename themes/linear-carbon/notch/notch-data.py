import json
import os
import re
import subprocess
import sys
import tomllib
import urllib.parse
import urllib.request
from pathlib import Path

STATE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "omarchy"
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "omarchy"
PALETTE_KEYS = ("darker_background", "foreground", "light_foreground", "accent",
                "dark_background", "background", "lighter_background", "selection")


def read_json(path):
    with path.open(encoding="utf-8") as stream:
        return json.loads(stream.read(2_000_000))


def palette(path):
    with Path(path).open("rb") as stream:
        colors = tomllib.load(stream)
    return {key: colors[key] for key in PALETTE_KEYS
            if isinstance(colors.get(key), str) and re.fullmatch(r"#[0-9a-fA-F]{6}", colors[key])}


def settings():
    try:
        config = read_json(CONFIG / "shell.json")
    except (OSError, ValueError):
        return {}
    for entry in config.get("plugins", []):
        if isinstance(entry, dict) and entry.get("id") == "omarchy.agents":
            return entry.get("settings", {})
    return {}


def agents():
    providers = settings().get("providers", {})
    records = []
    total = 0
    for path in sorted((STATE / "agents/usage").glob("*.json")):
        try:
            data = read_json(path)
            identifier = data.get("id")
            if not identifier or providers.get(identifier, {}).get("enabled") is False:
                continue
            subscribed = data.get("limits") or data.get("accounts") or data.get("balance") or data.get("tierLabel")
            has_data = any(data.get(key) for key in ("totalPrompts", "totalSessions", "activeDays", "todayPrompts",
                                                     "todaySessions", "limits", "accounts", "balance"))
            if not has_data and not (data.get("ready") and data.get("tierLabel")):
                continue
            total += int(data.get("todayTotalTokens") or 0)
            if subscribed:
                records.append({key: data[key] for key in ("id", "name", "tierLabel", "limits", "resetCredits") if key in data})
        except (OSError, TypeError, ValueError):
            continue
    try:
        order = read_json(STATE / "agents/order.json")
        positions = {identifier: index for index, identifier in enumerate(order)}
        records.sort(key=lambda record: positions.get(record["id"], len(positions)))
    except (OSError, TypeError, ValueError):
        pass
    return {"tokens": total, "providers": records}


def weather():
    location = read_json(Path.home() / ".local/state/omarchy/settings/weather.json")
    name = str(location.get("name", "")).strip()[:100]
    if not name:
        return {}
    encoded = urllib.parse.quote(name, safe="")
    url = "https://wttr.in/" + encoded + "?format=j1"
    with urllib.request.urlopen(url, timeout=8) as response:
        report = json.loads(response.read(500_000))
    current = report["current_condition"][0]
    return dict(
        name=name, temperature=current["temp_C"], feels=current["FeelsLikeC"],
        wind=current["windspeedKmph"], humidity=current["humidity"],
        condition=current["weatherDesc"][0]["value"][:60],
        forecast=[dict(date=day["date"], high=day["maxtempC"], low=day["mintempC"])
                  for day in report["weather"][1:3]],
    )


def quake_color(pids):
    # Runtime events may arrive together. Read the current workspace when
    # applying the color so a delayed open cannot leave a hidden console dark.
    def hyprland(command):
        return json.loads(subprocess.check_output(["hyprctl", "-j", command], timeout=2))

    on_theme = (STATE / "current/theme.name").read_text().strip() == "linear-carbon"
    visible = on_theme and any(m["specialWorkspace"]["name"] == "special:qconsole"
                               for m in hyprland("monitors"))
    agents = {w["pid"]: w for w in hyprland("clients") if w["class"] == "org.omarchy.agent"}
    pids = map(int, pids) if pids else (
        pid for pid, agent in agents.items() if agent["workspace"]["name"] == "special:qconsole")
    for pid in pids:
        agent = agents.get(pid)
        try:
            if not agent or Path(f"/proc/{pid}/comm").read_text().strip() != "ghostty":
                continue
            in_console = visible and agent["workspace"]["name"] == "special:qconsole"
            sequence = b"\x1b]11;#101010\x1b\\" if in_console else b"\x1b]111\x1b\\"
            children = subprocess.run(["ps", "--ppid", str(pid), "-o", "tty="],
                                      capture_output=True, text=True, timeout=2)
            for tty in set(children.stdout.split()):
                if not re.fullmatch(r"pts/[0-9]+", tty):
                    continue
                device = Path("/dev") / tty
                if not device.is_char_device() or device.stat().st_uid != os.getuid():
                    continue
                fd = os.open(device, os.O_WRONLY | os.O_NOCTTY | os.O_NONBLOCK)
                try:
                    os.write(fd, sequence)
                finally:
                    os.close(fd)
        except (OSError, subprocess.SubprocessError):
            continue


if __name__ == "__main__":
    readers = {"agents": agents, "weather": weather}
    try:
        mode = sys.argv[1]
        if mode == "quake-color":
            quake_color(sys.argv[2:])
            sys.exit(0)
        result = palette(sys.argv[2]) if mode == "palette" else readers[mode]()
        print(json.dumps(result, ensure_ascii=False))
    except (OSError, ValueError, IndexError, KeyError, TypeError, subprocess.SubprocessError):
        sys.exit(1)
