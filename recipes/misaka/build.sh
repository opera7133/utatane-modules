#!/bin/sh
set -eu
# Usage: build.sh native-source output-dir work-dir "arm64 x86_64"
source_dir=$1
output_dir=$2
work_dir=$3
architectures=$4
mkdir -p "$output_dir" "$work_dir"
set --
for architecture in $architectures; do
  case "$architecture" in arm64|x86_64) ;; *) exit 1 ;; esac
  set -- "$@" --arch "$architecture"
done
swift build --package-path "$source_dir" --scratch-path "$work_dir" -c release "$@" --product misaka
binary_dir=$(swift build --package-path "$source_dir" --scratch-path "$work_dir" -c release "$@" --show-bin-path)
cp "$binary_dir/libmisaka.dylib" "$output_dir/libmisaka.dylib"
install_name_tool -id @rpath/libmisaka.dylib "$output_dir/libmisaka.dylib"
codesign --force --sign - "$output_dir/libmisaka.dylib"
