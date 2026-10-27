#!/bin/sh
set -eu
SAORI_PRODUCT=playwavsound exec sh "$(dirname "$0")/../saori/build.sh" "$@"
