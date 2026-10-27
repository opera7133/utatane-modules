#!/bin/sh
set -eu
SAORI_PRODUCT=totp_saori exec sh "$(dirname "$0")/../saori/build.sh" "$@"
