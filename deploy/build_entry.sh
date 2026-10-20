#!/bin/bash

# Remember to chmod +x deploy/build_entry.sh on nuc after pulling latest file
#
# Build and deploy the single entry-point container. The entry point reads
# customer/league control data from the database at runtime, so it only needs
# rebuilding when its code changes (usually run manually, not every cron cycle).

# ── Config ────────────────────────────────────────────────────────────────────

set -uo pipefail

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)}"
cd "$REPO_DIR" || exit 1

if [ ! -t 1 ]; then
  # shellcheck source=/dev/null
  . "${REPO_DIR}/deploy/env.sh"
fi

DOCKERHUB_USER="${DOCKERHUB_USER:-shaggycamel}"
ENTRY_IMAGE="${ENTRY_IMAGE:-scs.nba.fty.league_dash_entry}"
BASE_IMAGE="scs.nba.fty.league_dash_base:latest"
TAG="${TAG:-latest}"
ENTRY_SLUG="${ENTRY_SLUG:-entry}"
DRY_RUN="${DRY_RUN:-0}"
REBUILD_BASE="${REBUILD_BASE:-0}"
PROVISION="${PROVISION:-0}"

DOCKERHUB_TOKEN="${DOCKERHUB_TOKEN:-}"

# shellcheck source=/dev/null
source "${REPO_DIR}/deploy/adapter.sh"

step() { printf "\n▶ %s\n\n" "$*"; }
fail() { printf "  ✘ %s\n" "$*" >&2; return 1; }

# ── Run ───────────────────────────────────────────────────────────────────────

if [ "$DRY_RUN" != "1" ]; then
  if [ "$REBUILD_BASE" = "1" ] || ! docker image inspect "$BASE_IMAGE" >/dev/null 2>&1; then
    step "Building base image ${BASE_IMAGE}"
    docker build -f ./docker/Dockerfile_base --progress=plain -t "$BASE_IMAGE" . || exit 1
  else
    step "Reusing base image ${BASE_IMAGE}"
  fi

  : "${DOCKERHUB_TOKEN:?DOCKERHUB_TOKEN not set}"
  step "Logging in to Docker Hub"
  echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USER" --password-stdin || exit 1
fi

FULL_IMAGE="${DOCKERHUB_USER}/${ENTRY_IMAGE}:${TAG}"

step "Building entry image: ${FULL_IMAGE}"
if [ "$DRY_RUN" != "1" ]; then
  docker build -f ./docker/Dockerfile_entry -t "$FULL_IMAGE" . || fail "entry image build"
  step "Pushing ${FULL_IMAGE}"
  docker push "$FULL_IMAGE" || fail "docker push"
else
  echo "[dry-run] docker build -f ./docker/Dockerfile_entry -t $FULL_IMAGE ."
fi

if [ "$PROVISION" = "1" ]; then
  step "Provisioning entry point"
  adapter_provision "$ENTRY_SLUG" "$FULL_IMAGE" "entry" || fail "provision"
fi

step "Deploying entry point (${ENTRY_SLUG})"
adapter_deploy "$ENTRY_SLUG" "$FULL_IMAGE" "entry" || fail "deploy"

printf "  → %s\n" "$(adapter_url "$ENTRY_SLUG")"
printf "\n✔ Entry point processed\n"
