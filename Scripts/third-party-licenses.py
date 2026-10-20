#!/usr/bin/env python3
"""Erzeugt Packages/QuillKit/Sources/QuillFeatures/Resources/ThirdPartyLicenses.txt.

Liest die Rust-Pakete im vorgebauten Automerge-Kern von automerge-swift (ADR-029):
alle normalen Abhängigkeiten von `uniffi_automerge` für macOS und iOS, auch solche nur
zum Übersetzen (Makros), lieber eine Lizenz zu viel. Gleiche Lizenztexte stehen nur
einmal. Pakete ohne Lizenzdatei bekommen den Text aus dem Repo ihres Projekts.

Braucht `cargo` (rustup, siehe docs/decisions.md, ADR-029 „Lizenzen“) und den Checkout
von automerge-swift unter Packages/QuillKit/.build/checkouts (einmal `swift build`).
Arbeitet in einem temporären Ordner, im Repo entsteht nur die Lizenzdatei.

Aufruf: python3 Scripts/third-party-licenses.py
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHECKOUT = os.path.join(ROOT, "Packages/QuillKit/.build/checkouts/automerge-swift")
OUTPUT = os.path.join(ROOT, "Packages/QuillKit/Sources/QuillFeatures/Resources/ThirdPartyLicenses.txt")
CARGO = shutil.which("cargo") or os.path.expanduser("~/.cargo/bin/cargo")
TARGETS = ["aarch64-apple-darwin", "aarch64-apple-ios"]
SWIFT_VERSION = "0.7.2"

# Pakete ohne Lizenzdatei im veröffentlichten Paket: Text aus dem Repo, gleiche Version.
UPSTREAM = {
    "automerge": "https://raw.githubusercontent.com/automerge/automerge/rust/automerge@{version}/LICENSE",
    "hexane": "https://raw.githubusercontent.com/automerge/automerge/rust/automerge@{automerge}/LICENSE",
    "uniffi": "https://raw.githubusercontent.com/mozilla/uniffi-rs/v{version}/LICENSE",
    "uniffi_checksum_derive": "https://raw.githubusercontent.com/mozilla/uniffi-rs/v{version}/LICENSE",
    "uniffi_core": "https://raw.githubusercontent.com/mozilla/uniffi-rs/v{version}/LICENSE",
    "uniffi_macros": "https://raw.githubusercontent.com/mozilla/uniffi-rs/v{version}/LICENSE",
    "uniffi_meta": "https://raw.githubusercontent.com/mozilla/uniffi-rs/v{version}/LICENSE",
}
LICENSE_FILE = re.compile(r"(?i)^(licen[cs]e|copying|notice|unlicense)")


def run(args, cwd):
    return subprocess.run(args, cwd=cwd, check=True, capture_output=True, text=True).stdout


def main():
    if not os.path.exists(CARGO):
        sys.exit("cargo fehlt (rustup, siehe ADR-029)")
    if not os.path.isdir(os.path.join(CHECKOUT, "rust")):
        sys.exit("Checkout von automerge-swift fehlt: zuerst swift build --package-path Packages/QuillKit")
    with tempfile.TemporaryDirectory() as temp:
        rust = os.path.join(temp, "rust")
        shutil.copytree(os.path.join(CHECKOUT, "rust"), rust)
        packages = set()
        for target in TARGETS:
            tree = run([CARGO, "tree", "--locked", "-e", "normal", "--prefix", "none", "--target", target, "--format", "{p}"], rust)
            for line in tree.splitlines():
                parts = line.replace(" (*)", "").replace(" (proc-macro)", "").split(" ")
                if len(parts) >= 2 and parts[0] != "uniffi_automerge":
                    packages.add((parts[0], parts[1].lstrip("v")))
        run([CARGO, "fetch", "--locked"], rust)
        meta = json.loads(run([CARGO, "metadata", "--locked", "--format-version", "1"], rust))

    info = {(p["name"], p["version"]): p for p in meta["packages"]}
    automerge = next(version for name, version in packages if name == "automerge")
    groups = {}
    for name, version in sorted(packages):
        package = info[(name, version)]
        base = os.path.dirname(package["manifest_path"])
        texts = []
        for file in sorted(os.listdir(base)):
            if LICENSE_FILE.match(file) and os.path.isfile(os.path.join(base, file)):
                with open(os.path.join(base, file), errors="replace") as handle:
                    texts.append((file, handle.read().strip()))
        if not texts:
            if name not in UPSTREAM:
                sys.exit(f"Keine Lizenzdatei und keine Quelle für {name} {version}")
            url = UPSTREAM[name].format(version=version, automerge=automerge)
            with urllib.request.urlopen(url) as response:
                texts.append((url, response.read().decode().strip()))
        for source, text in texts:
            key = hashlib.sha256(text.encode()).hexdigest()
            groups.setdefault(key, [text, []])[1].append(f"{name} {version} ({source})")

    with open(os.path.join(CHECKOUT, "LICENSE")) as handle:
        swift_license = handle.read().strip()
    lines = [
        f"automerge-swift {SWIFT_VERSION} (Automerge)",
        "https://github.com/automerge/automerge-swift",
        "",
        swift_license,
        "",
        "=" * 72,
        f"Rust-Pakete im vorgebauten Automerge-Kern (automergeFFI aus automerge-swift {SWIFT_VERSION})",
        "Paket, Version: Lizenz laut Paket",
        "",
    ]
    for name, version in sorted(packages):
        lines.append(f"{name} {version}: {info[(name, version)].get('license') or '–'}")
    lines += [
        "",
        "Die Pakete unter MPL-2.0 (uniffi) sind unverändert; ihr Quellcode:",
        "https://github.com/mozilla/uniffi-rs",
        "",
    ]
    for text, sources in sorted(groups.values(), key=lambda group: group[1][0]):
        lines += ["=" * 72, *sources, "-" * 72, text, ""]
    with open(OUTPUT, "w") as handle:
        handle.write("\n".join(lines).rstrip() + "\n")
    print(f"{len(packages)} Pakete, {len(groups)} Lizenztexte → {os.path.relpath(OUTPUT, ROOT)}")


if __name__ == "__main__":
    main()
