#!/bin/sh
set -eu
SAORI_PRODUCT=saori_cpuid exec sh "$(dirname "$0")/../saori/build.sh" "$@"
