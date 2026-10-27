#!/bin/sh
set -eu
SAORI_PRODUCT=timebkn exec sh "$(dirname "$0")/../saori/build.sh" "$@"
