#!/bin/sh
set -eu
SAORI_PRODUCT=mciaudior exec sh "$(dirname "$0")/../saori/build.sh" "$@"
