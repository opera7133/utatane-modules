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
swift build --package-path "$source_dir" --scratch-path "$work_dir" -c release "$@" --product kawari
binary_dir=$(swift build --package-path "$source_dir" --scratch-path "$work_dir" -c release "$@" --show-bin-path)
cp "$binary_dir/libkawari.dylib" "$output_dir/libkawari.dylib"
install_name_tool -id @rpath/libkawari.dylib "$output_dir/libkawari.dylib"
codesign --force --sign - "$output_dir/libkawari.dylib"
