#!/bin/bash
# Shared helpers. Source me:  source "$(dirname "$0")/lib.sh"
# Defines: ssh_run NODE CMD..., scp_to SRC NODE DST, scp_from NODE SRC DST, ssh_login NODE
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT="$(dirname "$HERE")"                 # .../evaluation/netpoke
REPO_ROOT="$(cd "$KIT/../.." && pwd)"    # the repository root (app/, src/, client/, evaluation/)
if [ ! -f "$HERE/config.env" ]; then echo "ERROR: copy cluster/config.env.example to cluster/config.env and edit it"; exit 1; fi
source "$HERE/config.env"
_addr() { local v="IP_$1"; local a="${!v:-}"; [ -n "$a" ] || { echo "ERROR: IP_$1 is empty in cluster/config.env" >&2; return 1; }; echo "$a"; }
_SSH=(-i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR
      -o ConnectTimeout=15 -o ServerAliveInterval=30 -o ServerAliveCountMax=20)
# Network drops: ssh/scp exit with 255 when the CONNECTION fails. Retry those (up to RETRIES times, WAIT s apart).
# Any other exit code is the remote command's own result and is returned unchanged (never retried).
RETRIES="${RETRIES:-8}"; WAIT="${WAIT:-15}"
_retry() { local i rc; for i in $(seq 1 "$RETRIES"); do "$@"; rc=$?; [ $rc -ne 255 ] && return $rc
  echo "  [net] connection failed (attempt $i/$RETRIES) - check your internet; retrying in ${WAIT}s" >&2; sleep "$WAIT"; done; return 255; }
ssh_run()   { local n="$1" a; shift; a=$(_addr "$n") || return 1; _retry ssh "${_SSH[@]}" "$SSH_USER@$a" "$*"; }
# scp: copying again is harmless, so retry on ANY failure
_retry_any() { local i; for i in $(seq 1 "$RETRIES"); do "$@" && return 0
  echo "  [net] copy failed (attempt $i/$RETRIES) - retrying in ${WAIT}s" >&2; sleep "$WAIT"; done; return 1; }
scp_to()    { local src="$1" n="$2" dst="$3" a; a=$(_addr "$n") || return 1; _retry_any scp -r "${_SSH[@]}" "$src" "$SSH_USER@$a:$dst"; }
scp_from()  { local n="$1" src="$2" dst="$3" a; a=$(_addr "$n") || return 1; _retry_any scp -r "${_SSH[@]}" "$SSH_USER@$a:$src" "$dst"; }
ssh_login() { local a; a=$(_addr "$1") || return 1; ssh "${_SSH[@]}" "$SSH_USER@$a"; }
