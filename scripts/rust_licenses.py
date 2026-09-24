"""Collect the pinned pasta dependency license texts for a binary package."""
import json
from pathlib import Path
import shutil
import subprocess

from catalog import ROOT, read_json, sha256, write_json


def collect(source, destination, cargo):
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source / "LICENSE", destination / "pasta-MIT.txt")
    command = [cargo, "+1.93.0"]
    packages = {}
    dependencies = set()
    for target in ("aarch64-apple-darwin", "x86_64-apple-darwin"):
        metadata = json.loads(subprocess.check_output(command + ["metadata", "--locked", "--format-version", "1",
                               "--filter-platform", target], cwd=source))
        packages.update({p["id"]: p for p in metadata["packages"]})
        tree = subprocess.check_output(command + ["tree", "--locked", "-p", "pasta_shiori", "--target", target,
                                      "--edges", "normal,build", "--prefix", "none", "--format", "{p}"], cwd=source, text=True)
        dependencies.update(tuple(line.split()[:2]) for line in tree.splitlines())
    overrides = {(item["name"], item["version"]): item for item in read_json(ROOT / "recipes/pasta/licenses/sources.json")}
    index = []
    for package in sorted(packages.values(), key=lambda p: (p["name"], p["version"])):
        if not package["source"] or (package["name"], "v" + package["version"]) not in dependencies:
            continue
        root = Path(package["manifest_path"]).parent
        target = destination / "dependencies" / f"{package['name']}-{package['version']}"
        texts = [p for p in root.rglob("*") if p.is_file() and
                 any(token in p.name.lower() for token in ("license", "licence", "copyright", "copying", "notice"))]
        if package["license_file"]:
            texts.append(root / package["license_file"])
        for text in sorted(set(texts)):
            copied = target / text.relative_to(root)
            copied.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(text, copied)
        if not texts:
            override = overrides.get((package["name"], package["version"]))
            if not override:
                raise ValueError(f"Missing license text: {package['name']} {package['version']}")
            text = ROOT / "recipes/pasta/licenses" / override["file"]
            if sha256(text) != override["sha256"]:
                raise ValueError("Vendored license checksum mismatch")
            target.mkdir(parents=True)
            shutil.copyfile(text, target / text.name)
            write_json(target / "source.json", override)
        # Preserve additional attribution, including the vendored BudouX models.
        if (root / "README.md").is_file():
            shutil.copyfile(root / "README.md", target / "README.md")
        index.append({"name": package["name"], "version": package["version"], "license": package["license"],
                      "repository": package["repository"], "directory": str(target.relative_to(destination))})
    if not index:
        raise ValueError("No dependency licenses were collected")
    write_json(destination / "dependencies.json", index)
