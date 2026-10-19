#!/bin/sh
set -eu
source_dir=$1
output_dir=$2
work_dir=$3
architectures=$4
SAORI_PRODUCT=proxy_ex sh "$(dirname "$0")/../saori/build.sh" "$@"
set --
for architecture in $architectures; do
  case "$architecture" in arm64|x86_64) ;; *) exit 1 ;; esac
  set -- "$@" --arch "$architecture"
done
swift build --package-path "$source_dir" --scratch-path "$work_dir" -c release "$@" --product mp3tag
binary_dir=$(swift build --package-path "$source_dir" --scratch-path "$work_dir" -c release "$@" --show-bin-path)
mkdir -p "$output_dir/../bin"
cp "$binary_dir/mp3tag" "$output_dir/../bin/mp3tag"
codesign --force --sign - "$output_dir/../bin/mp3tag"
