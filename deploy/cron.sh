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

# ── Config ────────────────────────────────────────────────────────────────────

set -uo pipefail

# cron provides a minimal PATH and no lock of its own; make docker/flock
# resolvable and serialise runs so a slow multi-league rebuild cannot overlap
# the next tick (mirrors the database cron).
export PATH=/usr/local/bin:/usr/bin:/bin

# Work from the repo root regardless of the invoking cwd (this script lives in
# deploy/, so the repo root is its parent directory)
REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)}"
cd "$REPO_DIR" || exit 1

LOCK_FILE="${LOCK_FILE:-${TMPDIR:-/tmp}/scs.nba.fty.league_dash.lock}"
exec 9>"$LOCK_FILE"
if ! flock -w 3600 9; then
  printf 'Another run is still in progress after 1h; skipping this tick.\n' >&2
  exit 1
fi

# Deploy secrets (DOCKERHUB_TOKEN, HUGGINGFACE_TOKEN, ...). Resolved after the cd so
# it is the repo's own file, not whatever $HOME happened to hold: the previous
# version sourced ./.profile before cd-ing, so under cron (cwd=$HOME) it read
# ~/.profile and ignored the repo copy entirely. A terminal means a human is
# driving, so values they already exported win.
if [ ! -t 1 ]; then
  for f in ./.deploy.env ./.profile "$HOME/.config/scs_deploy.env"; do
    if [ -f "$f" ]; then
      # shellcheck source=/dev/null
      . "$f"
      break
    fi
  done
fi

DOCKERHUB_USER="${DOCKERHUB_USER:-shaggycamel}"
IMAGE_NAME="scs.nba.fty.league_dash"
BASE_IMAGE="scs.nba.fty.league_dash_base:latest"
TAG="${TAG:-latest}"
# Season: pass NBA_SEASON through if set; otherwise leave it unset so the R
# default in core::nba_season() applies (one source of truth for the default).
SEASON="${NBA_SEASON:-}"
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

step() { printf "\n▶ %s\n\n" "$*"; }
fail() { printf "  ✘ %s\n" "$*" >&2; return 1; }

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
    -e NBA_SEASON="$SEASON" \
    -e LEAGUE_ID="${LEAGUE_ID:-}" \
    -v "${REPO_DIR}:/work" \
    -v "${CREDS_FILE}:/root/.config/scs_hub_credentials.ini:ro" \
    -w "/work/${PKG_DIR}" \
    "$R_IMAGE" "$@"
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
    run_r sh -c 'rm -f ./data/*.rda ./*.tar.gz' || fail "cleaning build artifacts"
    LEAGUE_ID="$league_id" run_r Rscript ./data-raw/_generate_league.R || fail "data generation"

    step "Building R package tarball"
    run_r R CMD build . || fail "package build"

    step "Building image: ${image}"
    docker build -f ./docker/Dockerfile -t "$image" . || fail "docker build"
  else
    step "[dry-run] generate + build image ${image}"
  fi

  step "Pushing ${image}"
  if [ "$DRY_RUN" != "1" ]; then
    docker push "$image" || fail "docker push"
  fi

  if [ "$PROVISION" = "1" ]; then
    step "Provisioning ${slug}"
    adapter_provision "$slug" "$image" "league" || fail "provision"
  fi

  step "Deploying ${slug}"
  adapter_deploy "$slug" "$image" || fail "deploy"

  printf "  → %s\n" "$(adapter_url "$slug")"
}

# ── Run ───────────────────────────────────────────────────────────────────────

build_base || exit 1

if [ "$DRY_RUN" != "1" ]; then
  : "${DOCKERHUB_TOKEN:?DOCKERHUB_TOKEN not set}"

  if [ "$SKIP_BASE" = "1" ] && [ -f "$BASE_CACHE" ]; then
    step "Reusing cached NBA base (SKIP_BASE=1): ${BASE_CACHE}"
  else
    if [ "$SKIP_BASE" = "1" ]; then
      printf '⚠ SKIP_BASE=1 but no base cache at %s; generating base\n' "$BASE_CACHE" >&2
    fi
    step "Generating shared NBA base (in ${R_IMAGE})"
    run_r Rscript ./data-raw/_generate_base.R || exit 1
  fi

  step "Logging in to Docker Hub"
  echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USER" --password-stdin || exit 1
fi

step "Fetching active leagues for season ${SEASON:-default}"
LEAGUES="$(list_leagues)"

if [ -z "$LEAGUES" ]; then
  printf "⚠ No leagues found for season %s\n" "${SEASON:-default}"
  exit 1
fi

FAILED=()

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

  if ( process_league "$PLATFORM" "$LEAGUE_ID" "$SLUG" ); then
    printf "✔ %s done\n" "$SLUG"
  else
    printf "✘ %s FAILED — continuing to next league\n" "$SLUG"
    FAILED+=("$SLUG")
  fi
done <<< "$LEAGUES"

# ── Entry point (optional: only rebuild when its code changes) ────────────────
if [ "$BUILD_ENTRY" = "1" ]; then
  step "Building/deploying entry point"
  if bash "${REPO_DIR}/deploy/build_entry.sh"; then
    printf "✔ entry point done\n"
  else
    printf "✘ entry point FAILED\n"
    FAILED+=("entry")
  fi
fi

if [ ${#FAILED[@]} -gt 0 ]; then
  printf "\n⚠ Failed leagues: %s\n" "${FAILED[*]}"
  exit 1
fi

printf "\n✔ All leagues processed\n"
