#!/usr/bin/env python3
"""Release-Messungen im Package mehrmals ausführen und zusammenfassen.

Aufruf: python3 Scripts/perf-package.py [Läufe, Standard 3]

Jeder Lauf startet `swift test -c release` für QuillPerformanceTests. Die Tests
selbst messen mit Aufwärmlauf plus fünf Läufen und prüfen ihre Schwellen; dieses
Skript sammelt die Zeilen `PERF <Name> <ms>` und zeigt pro Messung Median, Minimum
und Maximum über alle Läufe. Exit-Code 1, wenn ein Lauf rot war oder Werte fehlen.
"""
import re
import statistics
import subprocess
import sys
from pathlib import Path

PACKAGE = Path(__file__).resolve().parent.parent / "Packages" / "QuillKit"
COMMAND = ["swift", "test", "-c", "release", "-Xswiftc", "-enable-testing",
           "--filter", "QuillPerformanceTests"]


def main() -> int:
    runs = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    values: dict[str, list[float]] = {}
    failed = False
    for run in range(1, runs + 1):
        print(f"Lauf {run}/{runs} …", flush=True)
        result = subprocess.run(COMMAND, cwd=PACKAGE, capture_output=True, text=True)
        output = result.stdout + result.stderr
        found = re.findall(r"^PERF (\S+) ([0-9.]+)$", output, re.MULTILINE)
        if result.returncode != 0:
            failed = True
            for line in output.splitlines():
                if "✘" in line and "recorded an issue" not in line:
                    print("  " + line)
                if "Schwelle" in line or "Keine Schwelle" in line:
                    print("  " + line.strip())
        if not found:
            print("  Keine Messwerte gefunden.")
            failed = True
        for name, value in found:
            values.setdefault(name, []).append(float(value))

    print(f"\n{'Messung':<20} {'Median':>10} {'Min':>10} {'Max':>10}  (ms, {runs} Läufe)")
    for name in sorted(values):
        series = values[name]
        if len(series) != runs:
            print(f"{name}: nur {len(series)} von {runs} Werten")
            failed = True
        print(f"{name:<20} {statistics.median(series):>10.2f} {min(series):>10.2f} {max(series):>10.2f}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
