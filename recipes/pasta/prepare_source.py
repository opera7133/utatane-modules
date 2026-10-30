"""Prepare a disposable upstream checkout with the conventional macOS entry."""
from pathlib import Path
import shutil
import sys


def prepare(source, destination):
    source, destination = Path(source).resolve(), Path(destination).resolve()
    if source == destination or source in destination.parents:
        raise ValueError("Build copy must be outside the source checkout")
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(source, destination, ignore=shutil.ignore_patterns(".git", "target", ".DS_Store"))
    crate = destination / "crates/pasta_shiori"
    shutil.copyfile(Path(__file__).with_name("macos.rs"), crate / "src/macos.rs")
    lib = crate / "src/lib.rs"
    lib.write_text(lib.read_text() + '\n#[cfg(target_os = "macos")]\nmod macos;\n#[cfg(target_os = "macos")]\npub use macos::{load, loadu, request, unload};\n')
    manifest = crate / "Cargo.toml"
    manifest.write_text(manifest.read_text() + '\n[target.\'cfg(target_os = "macos")\'.dependencies]\nlibc = "0.2"\n')
    lock = destination / "Cargo.lock"
    text = lock.read_text()
    marker = 'name = "pasta_shiori"\n'
    before, section = text.split(marker, 1)
    section, after = section.split('\n[[package]]', 1)
    if '\n "libc",' in section:
        raise ValueError("Upstream now includes libc: review the adapter")
    section = section.replace('dependencies = [\n', 'dependencies = [\n "libc",\n', 1)
    lock.write_text(before + marker + section + '\n[[package]]' + after)
    return destination


if __name__ == "__main__":
    prepare(*sys.argv[1:])
