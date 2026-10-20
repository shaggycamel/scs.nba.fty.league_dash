#!/bin/bash

# Remember to chmod +x deploy/cron.sh on nuc after pulling latest file
#
# Single deploy entry point: build the base image, generate the shared NBA base,
# then generate/build/deploy one container per league via the deploy adapter
# (see deploy/adapter.sh). Data is customer-agnostic; the entry point maps
# customers to leagues at runtime.
#
# Run this directly (cronjobs run `deploy/cron.sh`). The entry-point container is
# deployed only when BUILD_ENTRY=1, since rebuilding it restarts the entry Space.
# SKIP_BASE=1 reuses the cached shared NBA base for fantasy-only refresh runs.
#
# Usage: deploy/cron.sh [daily|intraday|...]   (default: all)
# The cadence argument selects nothing here (every run deploys every active
# league); it is recorded on the util.update_log rows this run writes, mirroring
# database/cron.sh. Stages append 'dashboard:*' rows to util.update_log: a
# start/end bookend, dashboard:base when the shared base is (re)generated, one
# dashboard:<slug> per league, and dashboard:entry when BUILD_ENTRY=1. Every row
# records source (this repo's name, from the git remote) and job_kickoff (the run
# start, shared by all rows of the run). Logging is best-effort and needs a
# write-capable section (NBA_UPDATE_LOG_SECTION, default cockroach-write); it
# never fails the deploy.

# ── Config ────────────────────────────────────────────────────────────────────

set -uo pipefail

# cron provides a minimal PATH and no lock of its own; make docker/flock
# resolvable and serialise runs so a slow multi-league rebuild cannot overlap
# the next tick (mirrors the database cron).
export PATH=/usr/local/bin:/usr/bin:/bin

# Cadence: a bare run is 'all'; otherwise 'daily,intraday' == 'daily intraday'.
# Deduplicated and order-preserving, mirroring database/cron.sh. Only recorded
# on the util.update_log rows this run writes.
parse_cadence() {
  local arg part out="" seen=" " parts
  for arg in "$@"; do
    IFS=$' \t,' read -r -a parts <<< "$arg"
    for part in "${parts[@]}"; do
      [ -z "$part" ] && continue
      case "$seen" in *" $part "*) continue ;; esac
      seen="${seen}${part} "
      out="${out:+$out,}${part}"
    done
  done
  printf '%s' "${out:-all}"
}
DEPLOY_CADENCE="${DEPLOY_CADENCE:-$(parse_cadence "$@")}"
export DEPLOY_CADENCE

# Work from the repo root regardless of the invoking cwd (this script lives in
# deploy/, so the repo root is its parent directory)
REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)}"
cd "$REPO_DIR" || exit 1

# Repo name recorded in util.update_log.source. Derived from the checkout's
# origin (survives renames/forks), falling back to the canonical name when git
# or the remote is unavailable.
_remote="$(git -C "$REPO_DIR" config --get remote.origin.url 2>/dev/null)"
_repo="${_remote##*/}"
_repo="${_repo%.git}"
UPDATE_LOG_SOURCE="${UPDATE_LOG_SOURCE:-${_repo:-scs.nba.fty.league_dash}}"
export UPDATE_LOG_SOURCE

LOCK_FILE="${LOCK_FILE:-${TMPDIR:-/tmp}/scs.nba.fty.league_dash.lock}"
exec 9>"$LOCK_FILE"
if ! flock -w 3600 9; then
  printf 'Another run is still in progress after 1h; skipping this tick.\n' >&2
  exit 1
fi

# Deploy secrets (DOCKERHUB_TOKEN, HUGGINGFACE_TOKEN, ...) are loaded from
# ~/.config/scs_deploy.env, or SCS_DEPLOY_ENV when set. A terminal means a human
# is driving, so values they already exported win.
if [ ! -t 1 ]; then
  # shellcheck source=/dev/null
  . "${REPO_DIR}/deploy/env.sh"
fi

DOCKERHUB_USER="${DOCKERHUB_USER:-shaggycamel}"
IMAGE_NAME="scs.nba.fty.league_dash"
BASE_IMAGE="scs.nba.fty.league_dash_base:latest"
TAG="${TAG:-latest}"
EXCLUDE_LEAGUES="${EXCLUDE_LEAGUES:-}"
DRY_RUN="${DRY_RUN:-0}"
REBUILD_BASE="${REBUILD_BASE:-0}"
BUILD_ENTRY="${BUILD_ENTRY:-0}"
PROVISION="${PROVISION:-0}"
# SKIP_BASE=1 reuses the cached NBA base (data-raw/cache/base.rda) instead of
# regenerating it, for fantasy-only refresh runs between the daily base build.
SKIP_BASE="${SKIP_BASE:-0}"
BASE_CACHE="${BASE_CACHE:-${REPO_DIR}/dash_league/data-raw/cache/base.rda}"

DOCKERHUB_TOKEN="${DOCKERHUB_TOKEN:-}"
HUGGINGFACE_TOKEN="${HUGGINGFACE_TOKEN:-}"

# shellcheck source=/dev/null
source "${REPO_DIR}/deploy/adapter.sh"

STAGE=""
LAST_ERROR=""
step() { STAGE="$*"; printf "\n▶ %s\n\n" "$*"; }
fail() { LAST_ERROR="$*"; printf "  ✘ %s\n" "$*" >&2; return 1; }

# ── Base image (deps only, rebuilt rarely) ────────────────────────────────────

build_base() {
  if [ "$DRY_RUN" = "1" ]; then
    step "[dry-run] ensure base image ${BASE_IMAGE} exists"
    return 0
  fi

  if [ "$REBUILD_BASE" = "1" ] || ! docker image inspect "$BASE_IMAGE" >/dev/null 2>&1; then
    step "Building base image ${BASE_IMAGE}"
    docker build -f ./docker/Dockerfile_base --progress=plain -t "$BASE_IMAGE" . || fail "base image build failed"
  else
    step "Reusing base image ${BASE_IMAGE} (set REBUILD_BASE=1 to rebuild)"
  fi

  step "Verifying core in ${BASE_IMAGE}"
  docker run --rm "$BASE_IMAGE" R -e 'library(core); cat("core ok\n")' >/dev/null \
    || fail "core missing from ${BASE_IMAGE}"
}

# ── Run R inside the base image (host needs only Docker, not R/renv) ──────────

R_IMAGE="${R_IMAGE:-$BASE_IMAGE}"
# Credentials: mounted as a single file instead of the whole ~/.config. The
# container needs only the ini, and a directory mount also handed it every other
# config file on the host (dconf, systemd, Positron, ...). SCS_HUB_CREDENTIALS
# still works as an override, matching what the R code itself resolves.
CREDS_FILE="${CREDS_FILE:-${SCS_HUB_CREDENTIALS:-$HOME/.config/scs_hub_credentials.ini}}"
PKG_DIR="${PKG_DIR:-dash_league}"

run_r() {
  # docker silently creates a *directory* at a missing bind path, which then shows
  # up as a baffling R error, so check first.
  if [ ! -f "$CREDS_FILE" ]; then
    printf '✘ credentials file not found: %s\n' "$CREDS_FILE" >&2
    return 1
  fi
  docker run --rm \
    -e HOME=/root \
    -e RENV_CONFIG_AUTOLOADER_ENABLED=FALSE \
    -e NBA_DB_SECTION="${NBA_DB_SECTION:-cockroach-read}" \
    -e NBA_UPDATE_LOG_SECTION="${NBA_UPDATE_LOG_SECTION:-cockroach-write}" \
    -e UPDATE_LOG_SOURCE="$UPDATE_LOG_SOURCE" \
    -e UPDATE_LOG_KICKOFF="${UPDATE_LOG_KICKOFF:-}" \
    -e DEPLOY_CADENCE="$DEPLOY_CADENCE" \
    -e LEAGUE_ID="${LEAGUE_ID:-}" \
    -v "${REPO_DIR}:/work" \
    -v "${CREDS_FILE}:/root/.config/scs_hub_credentials.ini:ro" \
    -w "/work/${PKG_DIR}" \
    "$R_IMAGE" "$@"
}

# ── util.update_log (dashboard-update audit) ──────────────────────────────────

# Append one row to util.update_log, the table database/__main__.py also writes.
# Each row carries UPDATE_LOG_SOURCE (this repo) and UPDATE_LOG_KICKOFF (the run
# start). Best-effort: a failed write only warns, so logging can never fail the
# deploy. Skipped under DRY_RUN.
log_update() {
  local task="$1" status="$2" error="${3:-}"
  if [ "$DRY_RUN" = "1" ]; then
    printf '  · [dry-run] log %s (%s)\n' "$task" "$status"
    return 0
  fi
  NBA_UPDATE_LOG_SECTION="${NBA_UPDATE_LOG_SECTION:-cockroach-write}" \
    UPDATE_LOG_SOURCE="$UPDATE_LOG_SOURCE" \
    UPDATE_LOG_KICKOFF="$UPDATE_LOG_KICKOFF" \
    DEPLOY_CADENCE="$DEPLOY_CADENCE" \
    run_r Rscript ./data-raw/_log_update.R "$task" "$status" "$error" >/dev/null 2>&1 \
    || printf '  ⚠ could not write update_log row for %s\n' "$task" >&2
}

list_leagues() {
  if ! docker image inspect "$R_IMAGE" >/dev/null 2>&1; then
    if [ "$DRY_RUN" = "1" ]; then
      printf "⚠ base image %s not built; dry-run uses a placeholder league\n" "$R_IMAGE" >&2
      printf 'ESPN,95537,\n'
      return 0
    fi
    printf "✘ base image %s not found — build it first (deploy/cron.sh or REBUILD_BASE=1)\n" "$R_IMAGE" >&2
    return 1
  fi
  run_r Rscript ./data-raw/_list_leagues.R 2>/dev/null
}

# ── Per-league build/deploy ───────────────────────────────────────────────────

process_league() {
  local platform="$1"
  local league_id="$2"
  local slug="$3"
  local image="${DOCKERHUB_USER}/${IMAGE_NAME}-${slug}:${TAG}"

  if [ "$DRY_RUN" != "1" ]; then
    step "Generating data for ${slug} (LEAGUE_ID=${league_id})"
    # Clean inside the container: run_r executes as root and owns the generated
    # .rda/.tar.gz files, so the host user cannot remove them directly.
    # Each step stops at the first failure so STAGE/LAST_ERROR name the stage
    # that broke, for the dashboard:<slug> update_log row.
    run_r sh -c 'rm -f ./data/*.rda ./*.tar.gz' || { fail "cleaning build artifacts"; return 1; }
    LEAGUE_ID="$league_id" run_r Rscript ./data-raw/_generate_league.R || { fail "data generation"; return 1; }

    step "Building R package tarball"
    run_r R CMD build . || { fail "package build"; return 1; }

    step "Building image: ${image}"
    docker build -f ./docker/Dockerfile -t "$image" . || { fail "docker build"; return 1; }
  else
    step "[dry-run] generate + build image ${image}"
  fi

  step "Pushing ${image}"
  if [ "$DRY_RUN" != "1" ]; then
    docker push "$image" || { fail "docker push"; return 1; }
  fi

  if [ "$PROVISION" = "1" ]; then
    step "Provisioning ${slug}"
    adapter_provision "$slug" "$image" "league" || { fail "provision"; return 1; }
  fi

  step "Deploying ${slug}"
  adapter_deploy "$slug" "$image" || { fail "deploy"; return 1; }

  printf "  → %s\n" "$(adapter_url "$slug")"
}

# ── Run ───────────────────────────────────────────────────────────────────────

FAILED=""
# A space-separated list of the objects that failed; logged on the 'dashboard
# end' row. A scalar (not an array) so the EXIT trap is safe under set -u.
mark_failed() { FAILED="${FAILED:+$FAILED }$1"; }

# RUN_OK is set only on the fully successful path; any earlier exit leaves it 0,
# so the 'dashboard end' bookend records a failure.
RUN_OK=0
# The run's start, stamped on every row of this run (util.update_log.job_kickoff).
UPDATE_LOG_KICKOFF="${UPDATE_LOG_KICKOFF:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
export UPDATE_LOG_KICKOFF
log_update "dashboard start" ok
trap 'log_update "dashboard end" "$([ "$RUN_OK" = 1 ] && echo ok || echo fail)" "$FAILED"' EXIT

if ! build_base; then
  mark_failed "base image"
  exit 1
fi

if [ "$DRY_RUN" != "1" ]; then
  if [ -z "$DOCKERHUB_TOKEN" ]; then
    mark_failed "dockerhub token"
    printf '✘ DOCKERHUB_TOKEN not set\n' >&2
    exit 1
  fi

  if [ "$SKIP_BASE" = "1" ] && [ -f "$BASE_CACHE" ]; then
    step "Reusing cached NBA base (SKIP_BASE=1): ${BASE_CACHE}"
  else
    if [ "$SKIP_BASE" = "1" ]; then
      printf '⚠ SKIP_BASE=1 but no base cache at %s; generating base\n' "$BASE_CACHE" >&2
    fi
    step "Generating shared NBA base (in ${R_IMAGE})"
    if run_r Rscript ./data-raw/_generate_base.R; then
      log_update "dashboard:base" ok
    else
      log_update "dashboard:base" fail "base generation"
      mark_failed "base"
      exit 1
    fi
  fi

  step "Logging in to Docker Hub"
  echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USER" --password-stdin || { mark_failed "docker login"; exit 1; }
fi

step "Fetching active leagues for season ${SEASON:-default}"
LEAGUES="$(list_leagues)"

if [ -z "$LEAGUES" ]; then
  mark_failed "no leagues"
  printf "⚠ No leagues found for season %s\n" "${SEASON:-default}"
  exit 1
fi

while IFS=',' read -r PLATFORM LEAGUE_ID LEAGUE_SLUG; do
  [ -z "$PLATFORM" ] && continue

  case " ${EXCLUDE_LEAGUES} " in
    *" ${LEAGUE_ID} "*)
      printf "\n• Skipping league %s (excluded)\n" "$LEAGUE_ID"
      continue
      ;;
  esac

  if [ -n "${LEAGUE_SLUG:-}" ]; then
    SLUG="$(printf '%s' "$LEAGUE_SLUG" | tr '[:upper:]' '[:lower:]')"
  else
    SLUG="$(printf '%s-%s' "$PLATFORM" "$LEAGUE_ID" | tr '[:upper:]' '[:lower:]')"
  fi
  step "Processing league: ${SLUG} (${PLATFORM} ${LEAGUE_ID})"

  if process_league "$PLATFORM" "$LEAGUE_ID" "$SLUG"; then
    log_update "dashboard:$SLUG" ok
    printf "✔ %s done\n" "$SLUG"
  else
    log_update "dashboard:$SLUG" fail "${LAST_ERROR:-deploy}"
    printf "✘ %s FAILED — continuing to next league\n" "$SLUG"
    mark_failed "$SLUG"
  fi
done <<< "$LEAGUES"

# ── Entry point (optional: only rebuild when its code changes) ────────────────
if [ "$BUILD_ENTRY" = "1" ]; then
  step "Building/deploying entry point"
  if bash "${REPO_DIR}/deploy/build_entry.sh"; then
    log_update "dashboard:entry" ok
    printf "✔ entry point done\n"
  else
    log_update "dashboard:entry" fail "entry build/deploy"
    printf "✘ entry point FAILED\n"
    mark_failed "entry"
  fi
fi

# ── Health: never leave a Space RUNNING on a stale build ──────────────────────
# HF can keep serving a Space's previous build (RUNNING but on an old commit),
# which is how the entry ends up rejecting a valid password after a league-only
# deploy. Verify the entry is on its current commit, forcing a factory reboot if
# not. League Spaces are verified inside adapter_deploy. No-op for non-HF
# providers (the health helpers only exist for HF).
if [ "$DRY_RUN" != "1" ] && command -v hf_wait_healthy >/dev/null 2>&1; then
  step "Verifying the entry Space is on its current build"
  ENTRY_REPO="$(hf_space_id "${ENTRY_SLUG:-entry}")"
  if hf_wait_healthy "$ENTRY_REPO" "$(hf_space_head "$ENTRY_REPO")" "${HF_HEALTH_TIMEOUT:-900}"; then
    printf "✔ %s healthy\n" "$ENTRY_REPO"
  else
    printf "✘ %s FAILED health check\n" "$ENTRY_REPO"
    mark_failed "entry-health"
  fi
fi

if [ -n "$FAILED" ]; then
  printf "\n⚠ Failed leagues: %s\n" "$FAILED"
  exit 1
fi

RUN_OK=1
printf "\n✔ All leagues processed\n"
