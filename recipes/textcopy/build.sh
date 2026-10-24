#!/bin/sh
set -eu
SAORI_PRODUCT=textcopy exec sh "$(dirname "$0")/../saori/build.sh" "$@"
