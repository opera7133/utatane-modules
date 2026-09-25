#!/bin/sh
set -eu
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
swift build --package-path "$source_dir" --scratch-path "$work_dir" -c release "$@" --product yuhna
binary_dir=$(swift build --package-path "$source_dir" --scratch-path "$work_dir" -c release "$@" --show-bin-path)
cp "$binary_dir/libyuhna.dylib" "$output_dir/libyuhna.dylib"
install_name_tool -id @rpath/libyuhna.dylib "$output_dir/libyuhna.dylib"
codesign --force --sign - "$output_dir/libyuhna.dylib"
