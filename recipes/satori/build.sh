#!/bin/sh
set -eu
exec "${PYTHON:-python3}" "$(dirname "$0")/../../scripts/compile_cpp.py" satori "$@"
