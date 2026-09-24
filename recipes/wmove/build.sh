#!/bin/sh
set -eu
SAORI_PRODUCT=wmove exec sh "$(dirname "$0")/../saori/build.sh" "$@"
