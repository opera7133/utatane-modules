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
swift build --package-path "$source_dir" --scratch-path "$work_dir" -c release "$@" --product konoka
binary_dir=$(swift build --package-path "$source_dir" --scratch-path "$work_dir" -c release "$@" --show-bin-path)
cp "$binary_dir/libkonoka.dylib" "$output_dir/libkonoka.dylib"
install_name_tool -id @rpath/libkonoka.dylib "$output_dir/libkonoka.dylib"
codesign --force --sign - "$output_dir/libkonoka.dylib"
swift build --package-path "$source_dir" --scratch-path "$work_dir" -c release "$@" --product konoka-dictionary
mkdir -p "$output_dir/../bin"
cp "$binary_dir/konoka-dictionary" "$output_dir/../bin/konoka-dictionary"
codesign --force --sign - "$output_dir/../bin/konoka-dictionary"
