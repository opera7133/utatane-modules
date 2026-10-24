#!/bin/sh
set -eu
SAORI_PRODUCT=httpc exec sh "$(dirname "$0")/../saori/build.sh" "$@"
