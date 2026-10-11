#!/bin/bash
# Verify (and heal) HF Spaces are serving their current build -----------------
# HF sometimes leaves a Space RUNNING on its previous build, which serves a
# stale image -- e.g. the entry rejecting a valid password. This compares each
# Space's running commit against its repo HEAD and forces a factory reboot if
# they differ, so a manual reboot is never needed.
#
# deploy/cron.sh already health-checks the entry after every run; use this to
# check/heal on demand.
#
# Usage: deploy/health.sh [slug ...]        (default: entry)

if [ ! -t 1 ] && [ -f ./.profile ]; then
  # shellcheck source=/dev/null
  source ./.profile
fi

set -uo pipefail

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)}"
cd "$REPO_DIR" || exit 1

: "${HUGGINGFACE_TOKEN:?HUGGINGFACE_TOKEN is required for HF health checks}"

# shellcheck source=/dev/null
source "${REPO_DIR}/deploy/adapter.sh"

if ! command -v hf_wait_healthy >/dev/null 2>&1; then
  echo "health: the '${DEPLOY_PROVIDER:-hf}' provider has no health helpers" >&2
  exit 1
fi

SLUGS=("$@")
if [ ${#SLUGS[@]} -eq 0 ]; then
  SLUGS=("${ENTRY_SLUG:-entry}")
fi

rc=0
for slug in "${SLUGS[@]}"; do
  repo="$(hf_space_id "$slug")"
  head="$(hf_space_head "$repo")"
  if hf_wait_healthy "$repo" "$head" "${HF_HEALTH_TIMEOUT:-900}"; then
    printf "✔ %s serving %s\n" "$repo" "${head:0:12}"
  else
    printf "✘ %s FAILED health check\n" "$repo"
    rc=1
  fi
done

exit "$rc"
