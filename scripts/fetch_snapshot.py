#!/usr/bin/env python3
"""Fetch an exact signed staging snapshot for stable promotion."""

import argparse
import json
from pathlib import Path
import subprocess
from urllib.parse import urljoin, urlsplit
from urllib.request import Request, urlopen

from catalog import relative_path


def fetch(base, destination, public_key):
    if urlsplit(base).scheme != "https" or not base.endswith("/"):
        raise ValueError("Expected an HTTPS directory URL")
    if destination.exists():
        raise ValueError(f"Output already exists: {destination}")
    destination.mkdir(parents=True)

    def download(name, limit):
        relative_path(name)
        url = urljoin(base, name)
        if not url.startswith(base):
            raise ValueError(f"URL escapes catalog: {name}")
        request = Request(url, headers={"User-Agent": "Utatane-Modules-Catalog/1.0"})
        with urlopen(request, timeout=60) as response:
            if response.status != 200 or response.url != url:
                raise ValueError(f"Unexpected response for {name}")
            body = response.read(limit + 1)
        if len(body) > limit:
            raise ValueError(f"File is too large: {name}")
        path = destination / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(body)

    download("index.json", 2_000_000)
    download("index.sig", 64)
    result = subprocess.run(["openssl", "pkeyutl", "-verify", "-rawin", "-pubin",
                             "-inkey", str(public_key), "-sigfile", str(destination / "index.sig"),
                             "-in", str(destination / "index.json")],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if result.returncode:
        raise ValueError("Staging catalog signature does not match")
    index = json.loads((destination / "index.json").read_text())
    if index.get("channel") != "staging" or index.get("signed") is not True:
        raise ValueError("Expected a signed staging catalog")
    names = {"index.html", "catalog.css", "catalog.js"}
    for module in index["modules"]:
        names.add(module["instructions"])
        for artifact in module["artifacts"]:
            names.add(artifact["path"])
    for name in sorted(names):
        limit = 512_000_000 if name.startswith("artifacts/") else 1_000_000
        download(name, limit)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("base")
    parser.add_argument("destination", type=Path)
    parser.add_argument("--public-key", type=Path, required=True)
    args = parser.parse_args()
    fetch(args.base, args.destination, args.public_key)


if __name__ == "__main__":
    main()
