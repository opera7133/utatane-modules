#!/usr/bin/env python3
"""Run Utatane's module integration tests against a verified package."""
import argparse
import os
import re
from pathlib import Path
import subprocess
import tempfile

from catalog import ROOT, read_json, safe_extract, verify_package


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--utatane", type=Path, required=True)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--module", choices=("misaka-native", "minato", "pasta", "nise-shiori", "ese-shiori", "yuhna", "hisui", "shino", "akari", "kawari"), default="misaka-native")
    parser.add_argument("--host", type=Path, help="Use an existing native SHIORI host when testing conventional SHIORI")
    args = parser.parse_args()
    checkout = args.utatane.resolve()
    archive = args.package.resolve()
    entry = read_json(ROOT / f"catalog/modules/{args.module}.json")
    verify_package(archive, entry)
    host_header = checkout / "packages/shiori/external/module/MisakaBridge/include/misaka_host_bridge.h"
    if args.module == "misaka-native" and host_header.read_bytes() != (ROOT / "native/bridge/include/misaka_host_bridge.h").read_bytes():
        raise ValueError("Utatane's imported module header differs from native/bridge/include/misaka_host_bridge.h")
    suite_name = {"minato": "MinatoNativeTests", "pasta": "PastaNativeTests",
                  "nise-shiori": "NiseShioriNativeTests", "ese-shiori": "EseShioriNativeTests",
                  "yuhna": "YuhnaNativeTests", "hisui": "HisuiNativeTests",
                  "shino": "ShinoNativeTests", "akari": "AkariNativeTests",
                  "kawari": "KawariNativeTests"}.get(args.module)
    suite = checkout / (f"packages/plugin/Tests/{suite_name}.swift" if suite_name
                        else "packages/shiori/native/misaka/Tests/MisakaModuleIntegrationTests.swift")
    if not suite.is_file():
        raise ValueError("The selected Utatane checkout has no module integration tests")
    with tempfile.TemporaryDirectory(prefix="utatane-host-package-") as temporary:
        root = Path(temporary)
        safe_extract(archive, root)
        environment = dict(os.environ)
        if suite_name:
            library_name = {"nise-shiori": "libniseshiori.dylib"}.get(args.module, f"lib{args.module}.dylib")
            library = root / f"{args.module}/lib/{library_name}"
            host = args.host.resolve() if args.host else root / "utatane-shiori-host"
            if not args.host:
                subprocess.run(["sh", str(checkout / "Scripts/build-native-shiori-host.sh"), str(host)], check=True)
            environment.update({f"UTATANE_{args.module.upper().replace('-', '_')}_MODULE": str(library),
                                "UTATANE_NATIVE_SHIORI_HOST": str(host)})
            test_filter = suite_name.removesuffix("Tests")
            expected = (f"Suite {suite_name} passed",)
        else:
            library = root / "misaka-native/lib/libmisaka.dylib"
            environment["UTATANE_MISAKA_MODULE"] = str(library)
            test_filter = "UtataneModule|MisakaModule|MisakaPlugin|MisakaDistribution"
            expected = ("Suite MisakaModuleIntegrationTests passed", "Suite MisakaDistributionTests passed", "Suite MisakaPluginModuleTests passed")
        result = subprocess.run(["swift", "test", "--package-path", str(checkout / "packages"),
                        "--filter", test_filter],
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                       env=environment)
        print(result.stdout, end="", flush=True)
        result.check_returncode()
        if not re.search(r"Test run with [1-9][0-9]* tests?.*passed", result.stdout) or \
                any(name not in result.stdout for name in expected):
            raise ValueError("The real module integration suite did not execute successfully")


if __name__ == "__main__":
    main()
