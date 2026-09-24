#!/bin/sh
set -eu
if [ "$#" -ne 4 ]; then
    echo "usage: $0 source-directory output-directory work-directory 'arm64 x86_64'" >&2
    exit 64
fi
source_dir=$(cd "$1" && pwd)
mkdir -p "$2" "$3"
output_dir=$(cd "$2" && pwd)
work_dir=$(cd "$3" && pwd)
architectures=$4
cargo=${CARGO:-cargo}
toolchain=${MINATO_TOOLCHAIN:-1.93.0}
cd "$source_dir"
set --
for arch in $architectures; do
    case "$arch" in
        arm64) target=aarch64-apple-darwin ;;
        x86_64) target=x86_64-apple-darwin ;;
        *) echo "Unsupported architecture: $arch" >&2; exit 65 ;;
    esac
    set -- "$@" --target "$target"
done
[ "$#" -gt 0 ] || exit 65
MACOSX_DEPLOYMENT_TARGET=14.0 CARGO_TARGET_DIR="$work_dir" \
    "$cargo" "+$toolchain" build --locked --release --lib "$@"
set --
for arch in $architectures; do
    case "$arch" in arm64) target=aarch64-apple-darwin ;; x86_64) target=x86_64-apple-darwin ;; esac
    set -- "$@" "$work_dir/$target/release/libminato.dylib"
done
xcrun lipo -create "$@" -output "$output_dir/libminato.dylib"
install_name_tool -id @rpath/libminato.dylib "$output_dir/libminato.dylib"
codesign --force --sign - "$output_dir/libminato.dylib"
mkdir -p "$output_dir/licenses"
cp LICENSE "$output_dir/licenses/minato-MIT.txt"
cp THIRD-PARTY-LICENSES.toml "$output_dir/licenses/THIRD-PARTY-LICENSES.toml"
xcrun lipo -archs "$output_dir/libminato.dylib"
