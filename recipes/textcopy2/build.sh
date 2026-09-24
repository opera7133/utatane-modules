#!/bin/sh
set -eu
SAORI_PRODUCT=textcopy2 exec sh "$(dirname "$0")/../saori/build.sh" "$@"
