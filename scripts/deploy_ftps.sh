#!/usr/bin/env bash
set -euo pipefail

snapshot="${1:?signed snapshot directory is required}"
channel="${2:?staging or stable is required}"
root="${MODULES_DEPLOY_ROOT:?MODULES_DEPLOY_ROOT is required}"
[[ "$channel" == staging || "$channel" == stable ]]
[[ "$root" =~ ^/[A-Za-z0-9_./-]+$ ]]
[[ "$root" != / && "$root" != *'/../'* && "$root" != */.. && "$root" != *'/./'* ]]
test -f "$snapshot/index.json"
test -f "$snapshot/index.sig"

target="${root%/}"
if [[ "$channel" == staging ]]; then
  target="$target/preview"
fi

: "${DEPLOY_HOST:?DEPLOY_HOST is required}"
: "${DEPLOY_USERNAME:?DEPLOY_USERNAME is required}"
: "${DEPLOY_PASSWORD:?DEPLOY_PASSWORD is required}"

# Keep content-hashed ZIPs and old catalog versions available while the new
# signed index is uploaded. Rename each index file only after its upload ends.
lftp -u "$DEPLOY_USERNAME","$DEPLOY_PASSWORD" "ftp://$DEPLOY_HOST" <<LFTP
set cmd:fail-exit true
set ftp:ssl-force true
set ftp:ssl-protect-data true
set ssl:verify-certificate true
set net:max-retries 3
set net:timeout 20
mkdir -p "$target"
mirror --reverse --verbose --parallel=4 --exclude-glob index.json --exclude-glob index.sig "$snapshot" "$target"
put "$snapshot/index.sig" -o "$target/index.sig.next"
mv "$target/index.sig.next" "$target/index.sig"
put "$snapshot/index.json" -o "$target/index.json.next"
mv "$target/index.json.next" "$target/index.json"
bye
LFTP
