#!/bin/sh
set -eu
SAORI_PRODUCT=xpath exec sh "$(dirname "$0")/../saori/build.sh" "$@"
