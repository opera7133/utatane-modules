#!/bin/sh
set -eu
SAORI_PRODUCT=kenonoke exec sh "$(dirname "$0")/../saori/build.sh" "$@"
