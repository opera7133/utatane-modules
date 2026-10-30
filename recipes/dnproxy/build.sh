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
swift build --package-path "$source_dir" --scratch-path "$work_dir" -c release "$@" --product dnproxy
binary_dir=$(swift build --package-path "$source_dir" --scratch-path "$work_dir" -c release "$@" --show-bin-path)
cp "$binary_dir/libdnproxy.dylib" "$output_dir/libdnproxy.dylib"
install_name_tool -id @rpath/libdnproxy.dylib "$output_dir/libdnproxy.dylib"
codesign --force --sign - "$output_dir/libdnproxy.dylib"
repo_root=$(cd "$source_dir/.." && pwd)
# Portable IL has no CPU-specific apphost. Use the separately installed .NET runtime.
cd "$repo_root/managed"
"${DOTNET:-dotnet}" publish DnProxyHost/DnProxyHost.csproj -c Release --no-self-contained \
  -p:UseAppHost=false --nologo --ignore-failed-sources -o "$output_dir/../bin"
