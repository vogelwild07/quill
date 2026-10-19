#!/usr/bin/env python3
"""Kaltstart, Sidebar und Seitenwechsel messen und gegen Schwellen prüfen.

Aufruf:
  python3 Scripts/perf-ui.py                  Tests im Schema „Quill Profiling“ ausführen
  python3 Scripts/perf-ui.py --result X.xcresult   nur ein vorhandenes Ergebnis auswerten

Liest die Messwerte mit `xcresulttool` aus dem Ergebnis-Bundle und vergleicht den
Median jeder Messung mit ihrer Schwelle (`docs/performance.md`). Exit-Code 1, wenn
eine Schwelle gerissen ist, ein Test rot war oder ein Wert fehlt, z. B. weil ein
Signpost-Intervall nie endete.
"""
import argparse
import json
import statistics
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Test → Messung (Teil des Namens in xcresult) → Schwelle in ms.
LIMITS: dict[str, dict[str, float]] = {
    # Sidebar: Ziel 100 ms. Beim Start bremst das erste Layout des Fensters, nach ⌘N
    # SwiftData (docs/performance.md, Analyse); vom Nutzer so festgelegt am 19.10.2026.
    "testColdLaunch()": {"ApplicationLaunch": 1000, "launch": 1000, "sidebarLoad": 200},
    "testSidebarReload()": {"sidebarReload": 130},
    "testPageSwitch()": {"pageSwitch": 100},
}

UNITS = {"s": 1000.0, "ms": 1.0, "µs": 0.001}


def run_tests(result: Path) -> int:
    command = [
        "xcodebuild", "-project", str(ROOT / "Quill.xcodeproj"), "-scheme", "Quill Profiling",
        "-destination", "platform=macOS", "-resultBundlePath", str(result), "test",
    ]
    log = result.with_suffix(".log")
    with log.open("w") as handle:
        try:
            process = subprocess.run(command, stdout=handle, stderr=subprocess.STDOUT, timeout=600)
        except subprocess.TimeoutExpired:
            print(f"TIMEOUT nach 600 s (Log: {log})")
            subprocess.run(["pkill", "-x", "Quill Profiling"])
            return 124
    print(f"xcodebuild: Exit {process.returncode} (Log: {log})")
    return process.returncode


def metrics(result: Path) -> list[dict]:
    output = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "metrics", "--path", str(result)],
        capture_output=True, text=True, check=True,
    ).stdout
    return json.loads(output)


def evaluate(result: Path) -> bool:
    ok = True
    tests = {}
    for entry in metrics(result):
        name = entry.get("testIdentifier", "").split("/")[-1]
        tests[name] = [metric for run in entry.get("testRuns", []) for metric in run.get("metrics", [])]

    print(f"{'Test':<22} {'Messung':<15} {'Median':>9} {'Schwelle':>9}  Werte (ms)")
    for test, limits in LIMITS.items():
        found = tests.get(test)
        if not found:
            print(f"{test:<22} FEHLT: keine Messwerte")
            ok = False
            continue
        for key, limit in limits.items():
            metric = next((m for m in found if key in m.get("identifier", "") or f"({key})" in m.get("displayName", "")), None)
            values = (metric or {}).get("measurements") or []
            if not values:
                print(f"{test:<22} {key:<15} FEHLT")
                ok = False
                continue
            factor = UNITS.get(metric.get("unitOfMeasurement", "s"))
            if factor is None:
                print(f"{test:<22} {key:<15} unbekannte Einheit {metric.get('unitOfMeasurement')}")
                ok = False
                continue
            series = [value * factor for value in values]
            median = statistics.median(series)
            verdict = "ok" if median < limit else "ZU LANGSAM"
            ok = ok and median < limit
            listed = " ".join(f"{value:.1f}" for value in series)
            print(f"{test:<22} {key:<15} {median:>9.1f} {limit:>9.0f}  {listed}  {verdict}")
    return ok


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--result", type=Path)
    args = parser.parse_args()
    result = args.result
    exit_code = 0
    if result is None:
        result = Path(tempfile.mkdtemp(prefix="QuillPerformance-")) / "PerformanceUITests.xcresult"
        exit_code = run_tests(result)
        if exit_code == 124 or not result.exists():
            return 1
    ok = evaluate(result)
    if exit_code != 0:
        print("Mindestens ein Test war rot.")
    return 0 if ok and exit_code == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
