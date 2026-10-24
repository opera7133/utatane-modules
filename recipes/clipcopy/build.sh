#!/bin/sh
set -eu
SAORI_PRODUCT=clipcopy exec sh "$(dirname "$0")/../saori/build.sh" "$@"
